#!/usr/bin/env bash
# deploy-local.sh — installe une copie FIGÉE du serveur MCP hors du dossier de travail.
#
# Pourquoi : bin/google-mcp exécute le clone tel quel (cd $REPO + PYTHONPATH=$REPO).
# Tant que Claude Desktop pointe le clone, développer casse l'outil en service —
# et le code en chantier a accès aux vraies données Google. Ce script fige une
# version taggée dans ~/.local/share/google-mcp/<tag>/ et bascule le symlink
# « current ». Cf. fiche 0023.
#
# Usage :
#   ./scripts/deploy-local.sh                # déploie le tag de HEAD, bascule current
#   ./scripts/deploy-local.sh --print        # dry-run : dit ce qu'il ferait, n'écrit rien
#   ./scripts/deploy-local.sh --list         # versions déployées (* = courante)
#   ./scripts/deploy-local.sh --rollback X   # rebascule current sur la version X
#
# Refuse un arbre sale ou un HEAD non taggé : une version déployée doit être
# identifiable. Destination surchargeable via GWSA_DEPLOY_ROOT (utilisé par les tests).
#
# Ce script ne touche NI à la config de Claude Desktop NI aux comptes : il affiche
# à la fin le geste qui reste à l'humain (doctrine CLAUDE.md).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_ROOT="${GWSA_DEPLOY_ROOT:-$HOME/.local/share/google-mcp}"
CURRENT_LINK="$DEPLOY_ROOT/current"

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

# ── arguments ────────────────────────────────────────────────────
DRY=""
MODE="deploy"
ROLLBACK_TO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print|--dry-run) DRY=1 ;;
    --list) MODE="list" ;;
    --rollback) shift; ROLLBACK_TO="${1:-}"; MODE="rollback" ;;
    --rollback=*) ROLLBACK_TO="${1#*=}"; MODE="rollback" ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "argument inconnu « $1 » (voir --help)" ;;
  esac
  shift
done

current_version() { # nom de la version pointée par current (vide si aucune)
  [[ -L "$CURRENT_LINK" ]] || return 0
  basename "$(readlink "$CURRENT_LINK")"
}

point_current_at() { # point_current_at <version> — bascule atomique du symlink
  ln -sfn "$DEPLOY_ROOT/$1" "$CURRENT_LINK"
}

stop_broker() { # recycle le broker du couloir stable, sinon l'ancien code reste servi
  local gwsa="$CURRENT_LINK/bin/gwsa"
  [[ -x "$gwsa" ]] || { warn "gwsa introuvable dans la version déployée — broker non recyclé"; return 0; }
  "$gwsa" broker stop || warn "arrêt du broker en échec — le relancer à la main si besoin"
}

# ── --list ───────────────────────────────────────────────────────
if [[ "$MODE" == "list" ]]; then
  [[ -d "$DEPLOY_ROOT" ]] || die "aucun déploiement dans $DEPLOY_ROOT"
  cur="$(current_version)"
  found=""
  for d in "$DEPLOY_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    v="$(basename "$d")"
    if [[ "$v" == "current" ]]; then continue; fi
    found=1
    if [[ "$v" == "$cur" ]]; then echo "* $v"; else echo "  $v"; fi
  done
  [[ -n "$found" ]] || die "aucune version déployée dans $DEPLOY_ROOT"
  exit 0
fi

# ── --rollback ───────────────────────────────────────────────────
if [[ "$MODE" == "rollback" ]]; then
  [[ -n "$ROLLBACK_TO" ]] || die "usage : --rollback <version> (voir --list)"
  target="$DEPLOY_ROOT/$ROLLBACK_TO"
  [[ -d "$target" ]] || die "version « $ROLLBACK_TO » non déployée (voir --list)"
  if [[ -n "$DRY" ]]; then
    ok "dry-run : current pointerait sur $ROLLBACK_TO"; exit 0
  fi
  point_current_at "$ROLLBACK_TO"
  ok "current → $ROLLBACK_TO"
  stop_broker
  echo; echo "Redémarre Claude Desktop pour recharger le serveur."
  exit 0
fi

# ── déploiement ──────────────────────────────────────────────────
step "Contrôles"
command -v git >/dev/null 2>&1 || die "git est requis"
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$REPO_ROOT n'est pas un dépôt git"

[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
  || die "arbre de travail sale — commite ou remise tes modifications avant de déployer"
ok "arbre de travail propre"

VERSION="$(git -C "$REPO_ROOT" describe --exact-match --tags HEAD 2>/dev/null || true)"
[[ -n "$VERSION" ]] \
  || die "HEAD n'est pas taggé — pose un tag d'abord (ex. : git tag v0.2.0), sinon la version déployée n'est pas identifiable"
ok "version : $VERSION"

TARGET="$DEPLOY_ROOT/$VERSION"

if [[ -n "$DRY" ]]; then
  step "Dry-run"
  echo "déploierait   : $VERSION"
  echo "vers          : $TARGET"
  echo "current →     : $TARGET"
  if [[ -d "$TARGET" ]]; then warn "déjà déployé — seul le symlink current serait rebasculé"; fi
  echo "puis          : arrêt du broker + geste humain (brancher Claude Desktop)"
  exit 0
fi

step "Déploiement"
mkdir -p "$DEPLOY_ROOT"
if [[ -d "$TARGET" ]]; then
  ok "$VERSION déjà déployé — pas de réécriture"
else
  tmp="$(mktemp -d "$DEPLOY_ROOT/.tmp-XXXXXX")"
  # git archive n'exporte que les fichiers SUIVIS de HEAD : pas de .git/, pas de
  # worktrees, aucun fichier non commité. C'est ce qui garantit la copie figée.
  git -C "$REPO_ROOT" archive HEAD | tar -x -C "$tmp" \
    || { rm -rf "$tmp"; die "échec de l'export git archive"; }
  printf '%s\n' "$VERSION" > "$tmp/VERSION"
  mv "$tmp" "$TARGET"
  ok "copie figée : $TARGET"
fi

point_current_at "$VERSION"
ok "current → $VERSION"

step "Recyclage du broker"
# Sans ça, le broker déjà lancé continue de servir l'ANCIEN code : il ne se
# relance pas tout seul (ensure_broker_running ne redémarre pas un broker vivant).
stop_broker

step "Il reste un geste — à toi"
cat <<EOF
Brancher Claude Desktop sur la copie déployée :

  $CURRENT_LINK/scripts/install-claude-desktop.sh

puis redémarrer Claude Desktop. Vérification : le serveur doit annoncer
« $VERSION » (et non « dev », qui est la signature du dossier de travail).
EOF
