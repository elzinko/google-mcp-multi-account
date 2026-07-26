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
# Marche aussi depuis la copie installée : deploy-local.sh y note le chemin du
# clone source dans « .source », et ce script s'y redirige (la copie figée n'a
# pas de .git, donc pas de tags à consulter).
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
  shift
done

# ── où sont les versions ? ───────────────────────────────────────
# Lancé depuis la copie installée : pas de .git, donc on repart vers le clone.
SRC="$HERE"
if ! git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -s "$HERE/.source" ]]; then
    SRC="$(cat "$HERE/.source")"
    [[ -d "$SRC" ]] || die "clone source « $SRC » introuvable (noté dans $HERE/.source)"
    ok "clone source : $SRC"
  else
    die "ni dépôt git ni fichier .source dans $HERE — lance ce script depuis le clone"
  fi
fi
git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 || die "$SRC n'est pas un dépôt git"

step "Versions"
git -C "$SRC" fetch --quiet --tags 2>/dev/null || warn "fetch impossible — je travaille avec les tags locaux"

LATEST="$(git -C "$SRC" tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
[[ -n "$LATEST" ]] || die "aucune version publiée (aucun tag) — « ./scripts/release.sh » d'abord"

TARGET_VERSION="${WANT:-$LATEST}"
if [[ -n "$WANT" ]]; then
  git -C "$SRC" rev-parse -q --verify "refs/tags/$WANT" >/dev/null \
    || die "version « $WANT » inconnue (git -C $SRC tag pour la liste)"
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
  exit 0
fi

# ── installation ─────────────────────────────────────────────────
step "Installation de $TARGET_VERSION"
"$SRC/scripts/deploy-local.sh" --tag "$TARGET_VERSION" \
  || die "déploiement en échec — rien n'a basculé"

# ── branchement du client, seulement si nécessaire ───────────────
step "Branchement"
INSTALLER="$DEPLOY_ROOT/current/scripts/install-claude-desktop.sh"
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

CURRENT_CMD="$(entry_command)"
if [[ "$CURRENT_CMD" == "$EXPECTED" ]]; then
  ok "entrée déjà branchée sur current — config inchangée"
elif [[ -x "$INSTALLER" ]]; then
  "$INSTALLER" --config "$CONFIG" >/dev/null \
    && ok "entrée Claude Desktop branchée sur $EXPECTED" \
    || warn "branchement automatique en échec — lance « $INSTALLER »"
else
  warn "installeur introuvable ($INSTALLER) — branchement à faire à la main"
fi

# ── le poste de commande suit la version installée ───────────────
# gwsa doit être versionné comme le serveur MCP (fiche 0030) : sinon « gwsa
# unlock » exécute le code du clone sur les comptes du couloir stable.
# Prudence : on ne reprend QUE un lien symbolique dont la cible est un bin/gwsa
# du clone source ou d'une version déployée. Un fichier réel ou une cible
# étrangère est laissé intact.
link_cli() {
  local link expected target
  link="${GWSA_CLI_LINK:-$(command -v gwsa 2>/dev/null || true)}"
  expected="$DEPLOY_ROOT/current/bin/gwsa"

  [[ -n "$link" ]] || { warn "gwsa absent du PATH — lien non posé"; return 0; }
  [[ -x "$expected" ]] || { warn "gwsa absent de la copie installée — lien inchangé"; return 0; }

  if [[ ! -L "$link" ]]; then
    warn "« $link » n'est pas un lien symbolique — laissé tel quel"
    return 0
  fi
  target="$(readlink "$link")"
  if [[ "$target" == "$expected" ]]; then
    ok "gwsa du PATH déjà sur la copie installée"
    return 0
  fi
  case "$target" in
    "$SRC"/bin/gwsa|"$DEPLOY_ROOT"/*/bin/gwsa) ;;
    *) warn "gwsa du PATH pointe « $target » (hors projet) — laissé tel quel"; return 0 ;;
  esac
  if ln -sfn "$expected" "$link" 2>/dev/null; then
    ok "gwsa du PATH → $expected"
  else
    warn "impossible de réécrire « $link » — à refaire à la main : ln -sfn \"$expected\" \"$link\""
  fi
}
link_cli

step "Terminé — un dernier geste"
echo "Redémarre Claude Desktop (Cmd-Q puis relance) : le serveur MCP est lancé"
echo "par l'application, il ne se recharge pas tout seul."
echo
echo "Vérifier ensuite : le serveur doit annoncer « $TARGET_VERSION »."
