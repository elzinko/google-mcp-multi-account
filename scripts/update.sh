#!/usr/bin/env bash
# update.sh — update this machine's MCP, like an installed product.
#
# One command: takes the latest published version, installs it alongside the
# previous one, switches "current" to it, recycles the broker, and only
# wires up Claude Desktop if its entry is missing or points elsewhere.
#
# Usage:
#   ./scripts/update.sh              # installs the latest published version
#   ./scripts/update.sh --to v0.1.0  # …or a specific version (manual rollback)
#   ./scripts/update.sh --check      # reports installed / available, writes nothing
#   ./scripts/update.sh --force      # reinstalls even if already up to date
#
# Also works from the installed copy (relayed via ".source" to the clone).
# With no clone at all — installed via curl, or clone removed — it reads the
# latest version and its tarball from GitHub, no need to keep a clone (fiche 0020).
#
# Rollback (fiche 0091): each switch of "current" sets a "previous" link.
# To go back after an update that causes trouble:
#   mag revert                       # switches back to the previous version, directly
#   ./scripts/update.sh --to v0.1.0  # …or targeting a specific tag
#
# Example:
#   ./scripts/update.sh --to v0.1.0  # goes back precisely to v0.1.0
#   mag revert                       # goes back to the version installed just before
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_ROOT="${MAG_DEPLOY_ROOT:-${GWSA_DEPLOY_ROOT:-$HOME/.local/share/google-mcp}}"  # compat bi-nom (fiche 20260912000249823)

if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

# Re-ciblage des liens PATH mag/gma/gwsa — partagé avec deploy-local.sh
# (fiche 0081). Chargé ICI, TOUT DE SUITE — pas plus bas, juste avant l'appel
# à retarget_cli_links comme avant (fiche 20260905175129735 item 1). Quand ce
# script est invoqué depuis la copie INSTALLÉE ($0 = .../current/scripts/
# update.sh), $HERE contient encore le composant « current » : deploy-local.sh
# rebascule current sur la release CIBLE avant qu'on ait besoin du helper ; si
# on ne le source qu'après, la lecture traverse « current » déjà rebasculé et
# cherche le helper dans la release cible — absente si elle prédate ce helper,
# alors qu'il vivait bel et bien dans la release qui exécute CE process. En
# sourçant maintenant, la lecture traverse « current » tant qu'il pointe
# encore sur la bonne release.
LIBCLI="$HERE/scripts/lib/cli-link.sh"
CLI_LINK_LOADED=""
if [[ -f "$LIBCLI" ]]; then
  # shellcheck source=scripts/lib/cli-link.sh
  source "$LIBCLI"
  CLI_LINK_LOADED=1
fi

# ── arguments ────────────────────────────────────────────────────
CHECK=""; FORCE=""; WANT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--dry-run|--print) CHECK=1 ;;
    --force) FORCE=1 ;;
    --to) shift; WANT="${1:-}" ;;
    --to=*) WANT="${1#*=}" ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument « $1 » (see --help)" ;;
  esac
  # `|| break` : un flag à valeur en dernière position (« --to » nu) a déjà vidé
  # $@ ; sans ça, ce shift échoue et set -e avorte en silence (revue adversariale P3).
  shift || break
done

# ── où sont les versions ? ───────────────────────────────────────
# Deux chemins (fiche 0020) :
#   • Contributeur : un clone git est là (ici, ou noté dans .source) → tags git.
#   • Utilisateur  : aucun clone → dernier tag + tarball depuis GitHub.
LIB_GH="$(cd "$(dirname "$0")" && pwd)/lib-github-release.sh"
SRC="$HERE"
MODE_SRC="github"
# Détection par MARQUEURS, jamais par « git rev-parse » nu : rev-parse REMONTE
# l'arborescence, donc une install sous un ancêtre git (ex. $HOME en dépôt
# dotfiles) serait prise à tort pour un clone, ignorant .origin — l'update sans
# clone casserait, ou pire git-archiverait le mauvais dépôt (revue adversariale P1).
if [[ -e "$HERE/.git" ]] && git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1; then
  # Vrai clone À CE niveau : contributeur lançant depuis le clone.
  SRC="$HERE"; MODE_SRC="clone"
elif [[ -s "$HERE/.source" ]] && git -C "$(cat "$HERE/.source")" rev-parse --git-dir >/dev/null 2>&1; then
  # Copie installée DEPUIS un clone : relais vers le clone source noté dans .source.
  SRC="$(cat "$HERE/.source")"; ok "source clone: $SRC"; MODE_SRC="clone"
else
  # .origin (install sans clone), clone supprimé, ou rien d'exploitable → GitHub.
  # C'est ce qui rend l'update « standard » et robuste à un ancêtre git fortuit.
  MODE_SRC="github"
fi

step "Versions"
if [[ "$MODE_SRC" == "clone" ]]; then
  git -C "$SRC" fetch --quiet --tags 2>/dev/null || warn "fetch impossible — je travaille avec les tags locaux"
  LATEST="$(git -C "$SRC" tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
  [[ -n "$LATEST" ]] || die "no published version (no tag) — run « ./scripts/release.sh » first"
  TARGET_VERSION="${WANT:-$LATEST}"
  if [[ -n "$WANT" ]]; then
    git -C "$SRC" rev-parse -q --verify "refs/tags/$WANT" >/dev/null \
      || die "unknown version « $WANT » (git -C $SRC tag for the list)"
  fi
else
  command -v curl >/dev/null 2>&1 || die "curl is required to update without a clone"
  [[ -f "$LIB_GH" ]] || die "lib not found: $LIB_GH"
  # Restaurer le dépôt d'origine : si l'install venait d'un fork (GWSA_REPO),
  # .origin le note — mais un « mag update » ultérieur ne le relit pas, et on
  # interrogerait le dépôt par défaut (mauvais repo/tags). Revue Codex P2.
  # Un GWSA_REPO explicite dans l'environnement garde la priorité.
  if [[ -z "${GWSA_REPO:-}" && -s "$HERE/.origin" ]]; then
    _origin="$(cat "$HERE/.origin")"
    _origin="${_origin#github:}"
    # N'exporter qu'un « owner/repo » bien formé — un marqueur malformé
    # (ancienne provenance ssh mal parsée) est ignoré plutôt que propagé.
    [[ "$_origin" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] && export GWSA_REPO="$_origin"
  fi
  # Provenance inconnue : ce dossier vient d'un clone (.source présent mais
  # invalide → on est dans ce fallback) désormais absent, SANS .origin GitHub
  # exploitable et sans GWSA_REPO. On ne DEVINE pas le dépôt — sinon on
  # installerait le code d'upstream à la place du vrai (revue Codex). Refus.
  if [[ -z "${GWSA_REPO:-}" && -e "$HERE/.source" ]]; then
    die "unknown provenance: deployment came from a clone that is now gone, with no exploitable GitHub .origin — reinstall via « curl … | bash » (which records the provenance), or set GWSA_REPO=owner/repo"
  fi
  # shellcheck source=scripts/lib-github-release.sh
  source "$LIB_GH"
  ok "no clone — versions read from GitHub $(gh_repo)"
  LATEST="$(gh_latest_tag)" || die "could not reach GitHub (latest tag not found) — try again later"
  TARGET_VERSION="${WANT:-$LATEST}"
  if [[ -n "$WANT" ]]; then
    # Comme le chemin clone valide « refs/tags/$WANT » : sans clone, on confirme
    # le tag contre la liste publiée — sinon « --check --to <typo> » mentirait
    # (« installerait : v9.9.9 », rc 0). Revue Codex P2.
    gh_tag_exists "$WANT" \
      || die "version « $WANT » not found on GitHub $(gh_repo) (or GitHub unreachable)"
  fi
fi

INSTALLED=""
[[ -L "$DEPLOY_ROOT/current" ]] && INSTALLED="$(basename "$(readlink "$DEPLOY_ROOT/current")")"

echo "  installed  : ${INSTALLED:-none}"
echo "  available  : $LATEST"
[[ -n "$WANT" ]] && echo "  requested  : $WANT"

if [[ -n "$CHECK" ]]; then
  step "Check only (--check): nothing is written"
  if [[ "$INSTALLED" == "$TARGET_VERSION" ]]; then
    ok "already up to date"
  else
    echo "  would install : $TARGET_VERSION"
  fi
  exit 0
fi

if [[ "$INSTALLED" == "$TARGET_VERSION" && -z "$FORCE" ]]; then
  step "Nothing to do"
  ok "already up to date ($INSTALLED) — « --force » to reinstall anyway"
  # ne PAS sortir : on saute l'installation, mais on répare quand même les liens
  # du PATH plus bas (mag + alias gma/gwsa). Sinon une install antérieure qui n'a
  # que gma/gwsa n'obtiendrait jamais « mag » par « update » (Codex #114 round 3).
  SKIP_INSTALL=1
fi

# Bloc sauté si « déjà à jour » : on ne réinstalle ni ne rebranche, on ne fait
# que réparer les liens du PATH plus bas.
if [[ -z "${SKIP_INSTALL:-}" ]]; then
# ── installation ─────────────────────────────────────────────────
step "Installing $TARGET_VERSION"
if [[ "$MODE_SRC" == "clone" ]]; then
  "$SRC/scripts/deploy-local.sh" --tag "$TARGET_VERSION" \
    || die "deployment failed — nothing was switched over"
else
  # Depuis la copie installée : son propre deploy-local.sh sait tirer le tarball.
  "$HERE/scripts/deploy-local.sh" --github "$TARGET_VERSION" \
    || die "deployment failed — nothing was switched over"
fi

# ── branchement des clients, seulement si nécessaire ─────────────
# Deux clients, deux configs séparées : Claude Desktop (fichier JSON dédié) et
# Claude Code (le CLI `claude`, config ~/.claude.json). On branche les deux.
step "Wiring"
INSTALLER="$DEPLOY_ROOT/current/scripts/install-claude-desktop.sh"
CC_INSTALLER="$DEPLOY_ROOT/current/scripts/install-claude-code.sh"
CONFIG="${MAG_DESKTOP_CONFIG:-${GWSA_DESKTOP_CONFIG:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}}"  # compat bi-nom (fiche 20260912000249823)
EXPECTED="$DEPLOY_ROOT/current/bin/google-mcp"

entry_command() {
  [[ -f "$CONFIG" ]] || return 0
  /usr/bin/python3 - "$CONFIG" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
srv = (d.get("mcpServers") or {}).get("google-multi-account") or {}
print(srv.get("command") or "")
PY
}

# Claude Desktop
CURRENT_CMD="$(entry_command)"
if [[ "$CURRENT_CMD" == "$EXPECTED" ]]; then
  ok "Claude Desktop: already wired to current — config unchanged"
elif [[ -x "$INSTALLER" ]]; then
  "$INSTALLER" --config "$CONFIG" >/dev/null \
    && ok "Claude Desktop: wired to $EXPECTED" \
    || warn "Claude Desktop: automatic wiring failed — run « $INSTALLER »"
else
  warn "Desktop installer not found ($INSTALLER) — wire it by hand"
fi

# Claude Code (CLI) — best-effort : seulement si `claude` est installé. Le script
# délègue au CLI officiel (scope user) et est idempotent (fiche 0040).
if command -v claude >/dev/null 2>&1; then
  if [[ -x "$CC_INSTALLER" ]]; then
    "$CC_INSTALLER" >/dev/null \
      && ok "Claude Code (CLI): wired to $EXPECTED" \
      || warn "Claude Code: wiring failed — run « $CC_INSTALLER »"
  else
    warn "Claude Code installer not found ($CC_INSTALLER)"
  fi
else
  ok "CLI « claude » absent — Claude Code not wired (normal if you only use Desktop)"
fi

fi  # fin du bloc sauté quand « déjà à jour »

# ── le poste de commande suit la version installée ───────────────
# mag doit être versionné comme le serveur MCP (fiche 0030) : sinon « mag
# unlock » exécute le code du clone sur les comptes du couloir stable.
# Prudence : on ne reprend QUE un lien symbolique dont la cible est un bin/mag
# du clone source ou d'une version déployée. Un fichier réel ou une cible
# étrangère est laissé intact.
#
# La logique de re-ciblage est partagée avec deploy-local.sh --rollback
# (fiche 0081, socle du cluster updater 0091/0092) — voir scripts/lib/cli-link.sh,
# chargé tout en haut de ce script (item 1, fiche 20260905175129735) — AVANT
# que deploy-local.sh ne bascule « current » sur la release cible. Une copie
# déployée avant ce partage n'a pas ce fichier : on le signale plutôt que de
# faire échouer tout « update » (best-effort, comme le reste du branchement
# des liens du PATH).
if [[ -n "$CLI_LINK_LOADED" ]]; then
  retarget_cli_links "$SRC" "$DEPLOY_ROOT"
  MAG_RELINKED=1
else
  warn "retargeting helper not found ($LIBCLI) — PATH link not managed"
fi

step "Done — one last thing"
echo "Restart Claude Desktop (Cmd-Q then relaunch): the MCP server is launched"
echo "by the application, it does not reload on its own."
echo
echo "Then verify: the server should announce « $TARGET_VERSION »."

# Guide de refresh terminal (fiche 0092) : le nom canonique en ligne de
# commande est désormais « mag » (gwsa/gma restent invocables, dépréciés).
# Le shell garde en cache l'ancien chemin résolu : après une bascule, « mag »
# peut sembler introuvable tant qu'on n'a pas rafraîchi le shell courant.
#
# item 5 (fiche 20260905175129735) : l'ancienne garde testait « command -v mag »
# ICI, dans le PROCESS de update.sh — pas dans le shell interactif appelant.
# Comme retarget_cli_links vient de (re)poser « mag » juste avant, ce test
# réussit TOUJOURS dans ce process, masquant le guide précisément quand le
# shell appelant, lui, a encore l'ancien chemin en cache (le cas visé). On
# affiche donc le guide inconditionnellement dès qu'un (re)ciblage a eu lieu —
# on ne peut pas déduire l'état du cache du shell appelant depuis ce process.
if [[ -n "${MAG_RELINKED:-}" ]]; then
  echo
  echo "${Y}The canonical command-line name is « mag ».${N}"
  echo "This shell does not see it yet (cached path): open a new"
  echo "terminal, or run « hash -r » in this one, then retype « mag »."
  echo "(If this update was run from a pre-#114 release — before the"
  echo "gma/gwsa → mag rename —, the old update.sh does not know « mag »:"
  echo "re-run « mag update » once you are on a release ≥ #114.)"
fi

# Rappel de rollback (fiche 0091) : seulement quand une installation a eu lieu
# pour de vrai (pas le cas « déjà à jour », où rien n'a bougé).
if [[ -z "${SKIP_INSTALL:-}" ]]; then
  PREVIOUS_VERSION=""
  [[ -L "$DEPLOY_ROOT/previous" ]] && PREVIOUS_VERSION="$(basename "$(readlink "$DEPLOY_ROOT/previous")")"
  echo
  if [[ -n "$PREVIOUS_VERSION" ]]; then
    echo "To roll back: mag revert (or mag update --to $PREVIOUS_VERSION)."
  else
    # 1er install : aucune version précédente enregistrée — « mag revert »
    # échouerait encore. Il deviendra utile dès la prochaine mise à jour (revue 0091 P2).
    echo "To roll back after a future update: mag revert."
  fi
fi
