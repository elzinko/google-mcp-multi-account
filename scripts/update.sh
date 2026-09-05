#!/usr/bin/env bash
# update.sh — mettre à jour le MCP de ce poste, comme un produit installé.
#
# Une seule commande : prend la dernière version publiée, l'installe à côté de
# l'ancienne, bascule « current » dessus, recycle le broker, et ne branche
# Claude Desktop que si son entrée manque ou pointe ailleurs.
#
# Usage :
#   ./scripts/update.sh              # installe la dernière version publiée
#   ./scripts/update.sh --to v0.1.0  # …ou une version précise
#   ./scripts/update.sh --check      # dit installé / disponible, n'écrit rien
#   ./scripts/update.sh --force      # réinstalle même si déjà à jour
#
# Marche aussi depuis la copie installée (relais par « .source » vers le clone).
# Sans clone du tout — installé par curl, ou clone supprimé — il lit la dernière
# version et son tarball depuis GitHub, plus besoin de garder un clone (fiche 0020).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_ROOT="${GWSA_DEPLOY_ROOT:-$HOME/.local/share/google-mcp}"

if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

# ── arguments ────────────────────────────────────────────────────
CHECK=""; FORCE=""; WANT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--dry-run|--print) CHECK=1 ;;
    --force) FORCE=1 ;;
    --to) shift; WANT="${1:-}" ;;
    --to=*) WANT="${1#*=}" ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "argument inconnu « $1 » (voir --help)" ;;
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
  SRC="$(cat "$HERE/.source")"; ok "clone source : $SRC"; MODE_SRC="clone"
else
  # .origin (install sans clone), clone supprimé, ou rien d'exploitable → GitHub.
  # C'est ce qui rend l'update « standard » et robuste à un ancêtre git fortuit.
  MODE_SRC="github"
fi

step "Versions"
if [[ "$MODE_SRC" == "clone" ]]; then
  git -C "$SRC" fetch --quiet --tags 2>/dev/null || warn "fetch impossible — je travaille avec les tags locaux"
  LATEST="$(git -C "$SRC" tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
  [[ -n "$LATEST" ]] || die "aucune version publiée (aucun tag) — « ./scripts/release.sh » d'abord"
  TARGET_VERSION="${WANT:-$LATEST}"
  if [[ -n "$WANT" ]]; then
    git -C "$SRC" rev-parse -q --verify "refs/tags/$WANT" >/dev/null \
      || die "version « $WANT » inconnue (git -C $SRC tag pour la liste)"
  fi
else
  command -v curl >/dev/null 2>&1 || die "curl est requis pour mettre à jour sans clone"
  [[ -f "$LIB_GH" ]] || die "lib introuvable : $LIB_GH"
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
    die "provenance inconnue : déploiement issu d'un clone désormais absent, sans .origin GitHub — réinstalle via « curl … | bash » (qui note la provenance), ou précise GWSA_REPO=owner/repo"
  fi
  # shellcheck source=scripts/lib-github-release.sh
  source "$LIB_GH"
  ok "sans clone — versions lues depuis GitHub $(gh_repo)"
  LATEST="$(gh_latest_tag)" || die "impossible de joindre GitHub (dernier tag introuvable) — réessaie plus tard"
  TARGET_VERSION="${WANT:-$LATEST}"
  if [[ -n "$WANT" ]]; then
    # Comme le chemin clone valide « refs/tags/$WANT » : sans clone, on confirme
    # le tag contre la liste publiée — sinon « --check --to <typo> » mentirait
    # (« installerait : v9.9.9 », rc 0). Revue Codex P2.
    gh_tag_exists "$WANT" \
      || die "version « $WANT » introuvable sur GitHub $(gh_repo) (ou GitHub injoignable)"
  fi
fi

INSTALLED=""
[[ -L "$DEPLOY_ROOT/current" ]] && INSTALLED="$(basename "$(readlink "$DEPLOY_ROOT/current")")"

echo "  installée  : ${INSTALLED:-aucune}"
echo "  disponible : $LATEST"
[[ -n "$WANT" ]] && echo "  demandée   : $WANT"

if [[ -n "$CHECK" ]]; then
  step "Contrôle seul (--check) : rien n'est écrit"
  if [[ "$INSTALLED" == "$TARGET_VERSION" ]]; then
    ok "déjà à jour"
  else
    echo "  installerait : $TARGET_VERSION"
  fi
  exit 0
fi

if [[ "$INSTALLED" == "$TARGET_VERSION" && -z "$FORCE" ]]; then
  step "Rien à faire"
  ok "déjà à jour ($INSTALLED) — « --force » pour réinstaller quand même"
  # ne PAS sortir : on saute l'installation, mais on répare quand même les liens
  # du PATH plus bas (mag + alias gma/gwsa). Sinon une install antérieure qui n'a
  # que gma/gwsa n'obtiendrait jamais « mag » par « update » (Codex #114 round 3).
  SKIP_INSTALL=1
fi

# Bloc sauté si « déjà à jour » : on ne réinstalle ni ne rebranche, on ne fait
# que réparer les liens du PATH plus bas.
if [[ -z "${SKIP_INSTALL:-}" ]]; then
# ── installation ─────────────────────────────────────────────────
step "Installation de $TARGET_VERSION"
if [[ "$MODE_SRC" == "clone" ]]; then
  "$SRC/scripts/deploy-local.sh" --tag "$TARGET_VERSION" \
    || die "déploiement en échec — rien n'a basculé"
else
  # Depuis la copie installée : son propre deploy-local.sh sait tirer le tarball.
  "$HERE/scripts/deploy-local.sh" --github "$TARGET_VERSION" \
    || die "déploiement en échec — rien n'a basculé"
fi

# ── branchement des clients, seulement si nécessaire ─────────────
# Deux clients, deux configs séparées : Claude Desktop (fichier JSON dédié) et
# Claude Code (le CLI `claude`, config ~/.claude.json). On branche les deux.
step "Branchement"
INSTALLER="$DEPLOY_ROOT/current/scripts/install-claude-desktop.sh"
CC_INSTALLER="$DEPLOY_ROOT/current/scripts/install-claude-code.sh"
CONFIG="${GWSA_DESKTOP_CONFIG:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}"
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
  ok "Claude Desktop : déjà branché sur current — config inchangée"
elif [[ -x "$INSTALLER" ]]; then
  "$INSTALLER" --config "$CONFIG" >/dev/null \
    && ok "Claude Desktop : branché sur $EXPECTED" \
    || warn "Claude Desktop : branchement automatique en échec — lance « $INSTALLER »"
else
  warn "installeur Desktop introuvable ($INSTALLER) — branchement à faire à la main"
fi

# Claude Code (CLI) — best-effort : seulement si `claude` est installé. Le script
# délègue au CLI officiel (scope user) et est idempotent (fiche 0040).
if command -v claude >/dev/null 2>&1; then
  if [[ -x "$CC_INSTALLER" ]]; then
    "$CC_INSTALLER" >/dev/null \
      && ok "Claude Code (CLI) : branché sur $EXPECTED" \
      || warn "Claude Code : branchement en échec — lance « $CC_INSTALLER »"
  else
    warn "installeur Claude Code introuvable ($CC_INSTALLER)"
  fi
else
  ok "CLI « claude » absent — Claude Code non branché (normal si tu n'utilises que Desktop)"
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
# (fiche 0081, socle du cluster updater 0091/0092) — voir scripts/lib/cli-link.sh.
# Une copie déployée avant ce partage n'a pas ce fichier : on le signale
# plutôt que de faire échouer tout « update » (best-effort, comme le reste
# du branchement des liens du PATH).
LIBCLI="$(cd "$(dirname "$0")" && pwd)/lib/cli-link.sh"
if [[ -f "$LIBCLI" ]]; then
  # shellcheck source=scripts/lib/cli-link.sh
  source "$LIBCLI"
  retarget_cli_links "$SRC" "$DEPLOY_ROOT"
else
  warn "helper de re-ciblage introuvable ($LIBCLI) — lien du PATH non géré"
fi

step "Terminé — un dernier geste"
echo "Redémarre Claude Desktop (Cmd-Q puis relance) : le serveur MCP est lancé"
echo "par l'application, il ne se recharge pas tout seul."
echo
echo "Vérifier ensuite : le serveur doit annoncer « $TARGET_VERSION »."
