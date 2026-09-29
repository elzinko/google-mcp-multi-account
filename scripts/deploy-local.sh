#!/usr/bin/env bash
# deploy-local.sh — installs a FROZEN copy of the MCP server outside the working dir.
#
# Why: bin/google-mcp runs the clone as-is (cd $REPO + PYTHONPATH=$REPO).
# As long as Claude Desktop points at the clone, developing breaks the tool in
# service — and the code in progress has access to real Google data. This
# script freezes a tagged version under ~/.local/share/google-mcp/<tag>/ and
# switches the « current » symlink. See fiche 0023.
#
# Usage:
#   ./scripts/deploy-local.sh                # deploys HEAD's tag, switches current
#   ./scripts/deploy-local.sh --tag v0.2.0   # deploys THIS tag, regardless of HEAD
#   ./scripts/deploy-local.sh --print        # dry-run: says what it would do, writes nothing
#   ./scripts/deploy-local.sh --list         # deployed versions (* = current)
#   ./scripts/deploy-local.sh --rollback X   # switches current back to version X
#   ./scripts/deploy-local.sh --github v0.2.0 # …from the GitHub tarball, no clone (fiche 0020)
#   ./scripts/deploy-local.sh --check        # compares the client's wired binary to current
#     [--config PATH]  # client config path (defaults to Claude Desktop's own)
#     [--name NAME]    # MCP server entry to read (default: google-multi-account)
#
# Refuses a dirty tree or an untagged HEAD: a deployed version must be
# identifiable. Destination overridable via GWSA_DEPLOY_ROOT (used by tests).
#
# This script touches NEITHER Claude Desktop's config NOR the accounts: it
# prints at the end the step left for the human (CLAUDE.md doctrine).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_ROOT="${MAG_DEPLOY_ROOT:-${GWSA_DEPLOY_ROOT:-$HOME/.local/share/google-mcp}}"  # compat bi-nom (fiche 20260912000249823)
CURRENT_LINK="$DEPLOY_ROOT/current"
# « previous » — dernière version que current pointait AVANT la bascule en
# cours. Posé à CHAQUE bascule (déploiement comme --rollback) : c'est ce qui
# permet à « mag revert » (fiche 0091) de revenir en arrière sans connaître le
# tag exact, sans avoir à trier l'historique des versions déployées.
PREVIOUS_LINK="$DEPLOY_ROOT/previous"
# Source « GitHub sans clone » (fiche 0020) — sourcée à la demande dans --github.
LIB_GH="$(cd "$(dirname "$0")" && pwd)/lib-github-release.sh"
# Re-ciblage des liens PATH mag/gma/gwsa — partagé avec update.sh (fiche 0081).
LIB_CLI="$(cd "$(dirname "$0")" && pwd)/lib/cli-link.sh"
# Chargé ICI, tout de suite — PAS au moment de l'utiliser dans --rollback plus
# bas (fiche 20260905175129735 item 1). Quand ce script est invoqué à travers
# le lien « current » ($0 = .../current/scripts/deploy-local.sh), le chemin
# ci-dessus contient encore le composant « current » : si on ne source le
# fichier qu'APRÈS point_current_at (qui rebascule current sur la version
# CIBLE), la lecture traverse le symlink déjà rebasculé et cherche le helper
# dans la release cible — absente pour une release qui prédate ce helper —
# alors qu'il vivait bel et bien dans la release qui exécute CE process. En
# sourçant tout de suite (avant toute bascule), la lecture du fichier
# traverse « current » tant qu'il pointe encore sur la bonne release.
LIB_CLI_LOADED=""
if [[ -f "$LIB_CLI" ]]; then
  # shellcheck source=scripts/lib/cli-link.sh
  source "$LIB_CLI"
  LIB_CLI_LOADED=1
fi

# ── affichage (même convention que provision-gcp.sh) ─────────────
if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

# clone_github_origin <repo_root> → imprime « github:owner/repo » si le remote
# origin est un dépôt GitHub identifiable, sinon RIEN (refus d'un marqueur
# invalide). Gère https://, scp (git@github.com:owner/repo) et ssh://git@github.com/…
# Sert à (1) noter la provenance au deploy clone, (2) refuser de réutiliser un
# dossier venu d'un AUTRE dépôt (revue Codex).
clone_github_origin() {
  local url repo
  url="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
  # Préfiltre insensible à la casse (les noms d'hôte le sont — revue Codex).
  case "$(printf '%s' "$url" | tr 'A-Z' 'a-z')" in *github.com*) ;; *) return 0 ;; esac
  # Hôte EXACTEMENT github.com, schéma/hôte insensibles à la casse (classes
  # [Gg]… ) ; le chemin owner/repo, lui, reste sensible à la casse (on ne
  # lowercase pas l'URL). « ([^/@]*@)? » = userinfo optionnel, donc
  # « notgithub.com »/« github.com.evil.com » ne matchent pas. Port optionnel.
  # Formes : scp (git@github.com:owner/repo) · ssh://[user@]host[:port]/… · http(s)://…
  repo="$(printf '%s' "$url" | sed -E 's#^git@[Gg][Ii][Tt][Hh][Uu][Bb]\.[Cc][Oo][Mm]:#https://github.com/#; s#^[Ss][Ss][Hh]://([^/@]*@)?[Gg][Ii][Tt][Hh][Uu][Bb]\.[Cc][Oo][Mm](:[0-9]+)?/#https://github.com/#; s#^[Hh][Tt][Tt][Pp][Ss]?://([^/@]*@)?[Gg][Ii][Tt][Hh][Uu][Bb]\.[Cc][Oo][Mm](:[0-9]+)?/##; s#\.git$##; s#/$##')"
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] && printf 'github:%s' "$repo"
}

# ── arguments ────────────────────────────────────────────────────
DRY=""
MODE="deploy"
ROLLBACK_TO=""
WANT_TAG=""
SOURCE_TYPE="git"   # git (git archive du clone) | github (tarball d'un tag, sans clone)
GH_TAG=""
CHECK_CONFIG=""
CHECK_NAME="google-multi-account"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print|--dry-run) DRY=1 ;;
    --tag) shift; WANT_TAG="${1:-}" ;;
    --tag=*) WANT_TAG="${1#*=}" ;;
    --github) shift; GH_TAG="${1:-}"; SOURCE_TYPE="github" ;;
    --github=*) GH_TAG="${1#*=}"; SOURCE_TYPE="github" ;;
    --list) MODE="list" ;;
    --rollback) shift; ROLLBACK_TO="${1:-}"; MODE="rollback" ;;
    --rollback=*) ROLLBACK_TO="${1#*=}"; MODE="rollback" ;;
    --check) MODE="check" ;;
    --config) shift; CHECK_CONFIG="${1:-}" ;;
    --config=*) CHECK_CONFIG="${1#*=}" ;;
    --name) shift; CHECK_NAME="${1:-}" ;;
    --name=*) CHECK_NAME="${1#*=}" ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument « $1 » (see --help)" ;;
  esac
  # `|| break` : un flag à valeur en dernière position (« --github »/« --tag »/
  # « --rollback » nu) a déjà vidé $@ ; sans ça, ce shift échoue et set -e avorte
  # en silence avant le die d'usage (revue adversariale P3).
  shift || break
done

current_version() { # nom de la version pointée par current (vide si aucune)
  [[ -L "$CURRENT_LINK" ]] || return 0
  basename "$(readlink "$CURRENT_LINK")"
}

point_current_at() { # point_current_at <version> — bascule atomique du symlink,
  # en posant/rafraîchissant « previous » AVANT si current pointait déjà
  # ailleurs (fiche 0091 — socle de « mag revert »).
  local target="$1" old
  old="$(current_version)"
  if [[ -n "$old" && "$old" != "$target" ]]; then
    ln -sfn "$DEPLOY_ROOT/$old" "$PREVIOUS_LINK"
  fi
  ln -sfn "$DEPLOY_ROOT/$target" "$CURRENT_LINK"
}

stop_broker() { # recycle le broker du couloir stable, sinon l'ancien code reste servi
  local mag="$CURRENT_LINK/bin/mag"
  # rollback vers une release pré-renommage : le binaire s'appelle gwsa/gma
  [[ -x "$mag" ]] || mag="$CURRENT_LINK/bin/gwsa"
  [[ -x "$mag" ]] || mag="$CURRENT_LINK/bin/gma"
  [[ -x "$mag" ]] || { warn "binary not found in the deployed version — broker not recycled"; return 0; }
  "$mag" broker stop || warn "broker stop failed — restart it by hand if needed"
}

# ── --list ───────────────────────────────────────────────────────
if [[ "$MODE" == "list" ]]; then
  [[ -d "$DEPLOY_ROOT" ]] || die "no deployment in $DEPLOY_ROOT"
  cur="$(current_version)"
  found=""
  for d in "$DEPLOY_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    v="$(basename "$d")"
    # « previous » est un lien réservé (dernière bascule, fiche 0091), pas une
    # version déployée — item 3, fiche 20260905175129735.
    if [[ "$v" == "current" || "$v" == "previous" ]]; then continue; fi
    found=1
    if [[ "$v" == "$cur" ]]; then echo "* $v"; else echo "  $v"; fi
  done
  [[ -n "$found" ]] || die "no version deployed in $DEPLOY_ROOT"
  exit 0
fi

# ── --check ──────────────────────────────────────────────────────
# Lecture seule : compare le binaire réellement branché dans la config du
# client MCP (ex. Claude Desktop) au lien « current ». N'écrit jamais la
# config client — le correctif reste un geste humain (fiche 20260929172213000).
if [[ "$MODE" == "check" ]]; then
  CONFIG_PATH="$CHECK_CONFIG"
  if [[ -z "$CONFIG_PATH" ]]; then
    case "$(uname -s)" in
      Darwin) CONFIG_PATH="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
      Linux)  CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
      *) die "unsupported OS for auto-detection — use --config <path to the client's config file>" ;;
    esac
  fi
  [[ -f "$CONFIG_PATH" ]] || die "client config not found: $CONFIG_PATH"
  [[ -L "$CURRENT_LINK" ]] || die "no « current » deployment in $DEPLOY_ROOT — nothing to compare against"

  PYTHON="/usr/bin/python3"
  [[ -x "$PYTHON" ]] || PYTHON="$(command -v python3 || true)"
  [[ -n "$PYTHON" ]] || die "python3 not found"

  # Le python ne fait QUE lire (config + current) — aucune écriture, nulle part.
  out="$(
    CONFIG_PATH="$CONFIG_PATH" SERVER_NAME="$CHECK_NAME" CURRENT_LINK="$CURRENT_LINK" \
    DEPLOY_ROOT="$DEPLOY_ROOT" "$PYTHON" - <<'PY'
import json, os, sys

cfg = os.environ["CONFIG_PATH"]
name = os.environ["SERVER_NAME"]
current_link = os.environ["CURRENT_LINK"]
deploy_root = os.environ["DEPLOY_ROOT"]

raw = open(cfg, encoding="utf-8").read().strip()
try:
    data = json.loads(raw) if raw else {}
except json.JSONDecodeError as e:
    print(f"error=invalid JSON in {cfg}: {e}")
    sys.exit(3)

servers = data.get("mcpServers") if isinstance(data, dict) else None
entry = servers.get(name) if isinstance(servers, dict) else None
command = entry.get("command") if isinstance(entry, dict) else None
if not command:
    print(f"error=no entry « {name} » with a « command » in {cfg}")
    sys.exit(3)

def version_of(path):
    # Nom lisible : le composant juste sous DEPLOY_ROOT (ex. v1.0.0), sinon le
    # chemin brut (ex. binaire hors déploiement — clone de travail = « dev »).
    root = os.path.realpath(deploy_root) + os.sep
    if path.startswith(root):
        return path[len(root):].split(os.sep, 1)[0]
    return path

wired = os.path.realpath(command)
current = os.path.realpath(current_link)

print(f"wired={wired}")
print(f"wired_version={version_of(wired)}")
print(f"current={current}")
print(f"current_version={version_of(current)}")
# « current » désigne le dossier racine de la version déployée (ex. …/v1.0.0),
# alors que le binaire branché vit en dessous (ex. …/v1.0.0/bin/google-mcp) :
# aligné = le binaire branché vit SOUS ce dossier, pas égal à lui.
aligned = wired == current or wired.startswith(current + os.sep)
print("result=aligned" if aligned else "result=drift")
PY
  )"
  rc=$?

  wired=""; wired_version=""; current=""; current_version=""; result=""; error=""
  while IFS= read -r line; do
    case "$line" in
      wired=*)           wired="${line#wired=}" ;;
      wired_version=*)   wired_version="${line#wired_version=}" ;;
      current=*)         current="${line#current=}" ;;
      current_version=*) current_version="${line#current_version=}" ;;
      result=*)          result="${line#result=}" ;;
      error=*)           error="${line#error=}" ;;
    esac
  done <<< "$out"

  [[ -n "$error" ]] && die "$error"
  [[ "$rc" -ne 0 && -z "$result" ]] && die "--check failed (code $rc)"

  case "$result" in
    aligned)
      ok "client and « current » agree: $current_version ($current)"
      exit 0 ;;
    drift)
      warn "drift detected — the client is NOT wired to « current »"
      echo "  client (« $CHECK_NAME ») : $wired_version  ($wired)"
      echo "  current                  : $current_version  ($current)"
      echo
      echo "Fix (human step): $CURRENT_LINK/scripts/install-claude-desktop.sh"
      exit 1 ;;
    *)
      die "unexpected --check status: « $result »" ;;
  esac
fi

# ── --rollback ───────────────────────────────────────────────────
if [[ "$MODE" == "rollback" ]]; then
  [[ -n "$ROLLBACK_TO" ]] || die "usage: --rollback <version> (see --list)"
  # « previous » est un lien RÉSERVÉ (dernière bascule, fiche 0091), pas une
  # version : le test « -d » ci-dessous l'accepterait, mais point_current_at
  # écrase « previous » AVANT d'y faire pointer current, ce qui perdrait sa
  # vraie cible (item 3, fiche 20260905175129735).
  [[ "$ROLLBACK_TO" != "previous" ]] \
    || die "« previous » is a reserved link (points at the last switch), not a deployed version — see « --list » for valid versions"
  target="$DEPLOY_ROOT/$ROLLBACK_TO"
  [[ -d "$target" ]] || die "version « $ROLLBACK_TO » not deployed (see --list)"
  if [[ -n "$DRY" ]]; then
    ok "dry-run: current would point to $ROLLBACK_TO"; exit 0
  fi
  point_current_at "$ROLLBACK_TO"
  ok "current → $ROLLBACK_TO"
  stop_broker
  # Sans ça, un rollback vers une release pré-renommage (bin/gwsa/bin/gma
  # seulement) laisse les liens PATH pointer vers un bin/mag qui n'existe
  # plus : toutes les commandes cassées après un rollback « réussi » (Codex
  # #114 round 5, fiche 0081). Même cible que le repli déjà appliqué par
  # stop_broker ci-dessus. Best-effort : une copie déployée avant ce partage
  # n'a pas ce fichier — on le signale plutôt que de faire échouer le rollback.
  if [[ -n "$LIB_CLI_LOADED" ]]; then
    retarget_cli_links "$REPO_ROOT" "$DEPLOY_ROOT"
  else
    warn "retargeting helper not found ($LIB_CLI) — PATH links not managed"
  fi
  echo; echo "Restart Claude Desktop to reload the server."
  exit 0
fi

# ── déploiement ──────────────────────────────────────────────────
step "Checks"
SOURCE_REF=""
if [[ "$SOURCE_TYPE" == "github" ]]; then
  # Chemin « sans clone » (fiche 0020) : on ne fige pas une référence git locale
  # mais le tarball que GitHub publie pour le tag demandé.
  [[ -n "$GH_TAG" ]] || die "usage: --github <tag> (e.g. --github v0.2.0)"
  command -v curl >/dev/null 2>&1 || die "curl is required for --github"
  [[ -f "$LIB_GH" ]] || die "lib not found: $LIB_GH"
  # shellcheck source=scripts/lib-github-release.sh
  source "$LIB_GH"
  VERSION="$GH_TAG"
  ok "version: $VERSION (GitHub release $(gh_repo) — no clone)"
else
  command -v git >/dev/null 2>&1 || die "git is required"
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$REPO_ROOT is not a git repository"

  if [[ -n "$WANT_TAG" ]]; then
    # --tag archive une référence git, jamais l'arbre de travail : on peut donc
    # installer une version pendant qu'on développe autre chose à côté.
    git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$WANT_TAG" >/dev/null \
      || die "unknown tag « $WANT_TAG » in $REPO_ROOT (git tag for the list; git fetch --tags if needed)"
    VERSION="$WANT_TAG"
    SOURCE_REF="refs/tags/$WANT_TAG"
    ok "version: $VERSION (requested tag — working tree ignored)"
  else
    [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
      || die "dirty working tree — commit or stash your changes before deploying"
    ok "clean working tree"

    VERSION="$(git -C "$REPO_ROOT" describe --exact-match --tags HEAD 2>/dev/null || true)"
    [[ -n "$VERSION" ]] \
      || die "HEAD is not tagged — tag it first (e.g.: git tag v0.2.0), otherwise the deployed version is not identifiable"
    SOURCE_REF="HEAD"
    ok "version: $VERSION"
  fi
fi

TARGET="$DEPLOY_ROOT/$VERSION"

if [[ -n "$DRY" ]]; then
  step "Dry-run"
  echo "would deploy  : $VERSION"
  echo "source        : $([[ "$SOURCE_TYPE" == "github" ]] && echo "GitHub tarball $(gh_repo)" || echo "git archive ${SOURCE_REF}")"
  echo "to            : $TARGET"
  echo "current →     : $TARGET"
  if [[ -d "$TARGET" ]]; then warn "already deployed — only the current symlink would be switched"; fi
  echo "then          : broker stop + human step (wire Claude Desktop)"
  exit 0
fi

step "Deployment"
mkdir -p "$DEPLOY_ROOT"
if [[ -d "$TARGET" ]]; then
  # Cible RÉUTILISÉE : valider avant de basculer (revue Codex, cibles réutilisées).
  if [[ "$SOURCE_TYPE" == "github" ]]; then
    # (a) une version legacy (ancien deploy clone) n'a pas d'updater sans clone —
    #     ne jamais y basculer current/mag, sinon « mag update » redeviendrait
    #     dépendant d'un clone (P1).
    [[ -f "$TARGET/scripts/lib-github-release.sh" ]] \
      || die "$VERSION already deployed but predates the no-clone updater — current is not switched to it (remove « $TARGET » or go through a clone)"
    # (b) collision de tag ENTRE DÉPÔTS : ne pas réutiliser un dossier venu d'un
    #     autre repo (son .origin diffère), sinon current basculerait sur le code
    #     d'un autre dépôt et les updates suivants viseraient la mauvaise source (P2).
    [[ "$(cat "$TARGET/.origin" 2>/dev/null)" == "github:$(gh_repo)" ]] \
      || die "$VERSION already deployed from a different repo (.origin ≠ github:$(gh_repo)) — remove « $TARGET » or choose a different GWSA_DEPLOY_ROOT"
  else
    # Mode clone : même risque de collision de tag entre dépôts (ex. dossier posé
    # depuis upstream, puis --tag depuis un fork). Si la provenance du dossier
    # diffère du remote de CE clone, ne pas le réutiliser (revue Codex). On ne
    # refuse que quand les deux provenances sont connues et diffèrent.
    _want="$(clone_github_origin "$REPO_ROOT")"; _have="$(cat "$TARGET/.origin" 2>/dev/null || true)"
    [[ -z "$_want" || -z "$_have" || "$_have" == "$_want" ]] \
      || die "$VERSION already deployed from a different repo ($_have ≠ $_want) — remove « $TARGET » or choose a different GWSA_DEPLOY_ROOT"
  fi
  ok "$VERSION already deployed — not overwritten"
else
  tmp="$(mktemp -d "$DEPLOY_ROOT/.tmp-XXXXXX")"
  if [[ "$SOURCE_TYPE" == "github" ]]; then
    gh_download_version "$VERSION" "$tmp" \
      || { rm -rf "$tmp"; die "download/extraction of tarball $VERSION failed (GitHub reachable? tag exists?)"; }
    # Garde-fou (revue Codex P1) : ne jamais basculer « current » — donc le mag
    # du PATH — sur une version ANTÉRIEURE à l'update sans clone. Son update.sh
    # exigerait un clone (.git/.source), et tout « mag update » suivant mourrait.
    [[ -f "$tmp/scripts/lib-github-release.sh" ]] \
      || { rm -rf "$tmp"; die "$VERSION predates the no-clone updater (no built-in updater) — install it from a clone if you need it"; }
    # Marqueur d'origine : update.sh sait qu'il doit re-tirer depuis GitHub, pas
    # depuis un clone. Pas de .source — il n'y a pas de clone (fiche 0020).
    printf '%s\n' "github:$(gh_repo)" > "$tmp/.origin"
  else
    # git archive n'exporte que les fichiers SUIVIS de HEAD : pas de .git/, pas de
    # worktrees, aucun fichier non commité. C'est ce qui garantit la copie figée.
    git -C "$REPO_ROOT" archive "$SOURCE_REF" | tar -x -C "$tmp" \
      || { rm -rf "$tmp"; die "git archive export failed"; }
    # Le clone source, pour que « update.sh » sache où chercher les versions
    # quand il est lancé depuis la copie installée (qui n'a pas de .git).
    printf '%s\n' "$REPO_ROOT" > "$tmp/.source"
    # Provenance : note aussi le dépôt distant pour qu'un « mag update » vise le
    # BON dépôt si le clone est supprimé (fallback GitHub) — sinon un déploiement
    # depuis un fork retomberait sur upstream (revue Codex). Best-effort.
    _ori="$(clone_github_origin "$REPO_ROOT")"
    [[ -n "$_ori" ]] && printf '%s\n' "$_ori" > "$tmp/.origin"
  fi
  printf '%s\n' "$VERSION" > "$tmp/VERSION"
  mv "$tmp" "$TARGET"
  ok "frozen copy: $TARGET"
fi

point_current_at "$VERSION"
ok "current → $VERSION"

step "Broker recycling"
# Sans ça, le broker déjà lancé continue de servir l'ANCIEN code : il ne se
# relance pas tout seul (ensure_broker_running ne redémarre pas un broker vivant).
stop_broker

step "One step left — up to you"
cat <<EOF
Wire Claude Desktop to the deployed copy:

  $CURRENT_LINK/scripts/install-claude-desktop.sh

then restart Claude Desktop. To verify: the server should announce
« $VERSION » (not « dev », which is the working-directory signature).
EOF
