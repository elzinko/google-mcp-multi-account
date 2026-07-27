#!/usr/bin/env bash
# install-claude-code.sh — branche ce serveur MCP dans Claude Code (le CLI `claude`).
#
# Pendant de install-claude-desktop.sh, mais pour l'AUTRE client : Claude Code a
# sa propre config (`~/.claude.json`), séparée de Claude Desktop. On enregistre
# le serveur au **scope user** (visible depuis n'importe quel dossier) via le CLI
# officiel — jamais en éditant `~/.claude.json` à la main (fichier d'état vivant :
# permissions, historique, projets ; l'éditer risque la corruption + une course
# avec un Claude Code ouvert). `claude mcp add` est le chemin supporté.
#
# Usage :
#   ./scripts/install-claude-code.sh                 # branche (ou re-pointe)
#   ./scripts/install-claude-code.sh --print         # dry-run : montre la commande
#   ./scripts/install-claude-code.sh --name autre    # nom d'entrée personnalisé
#   ./scripts/install-claude-code.sh --port 4881     # broker dédié à ce couloir
#
# Idempotent : relançable sans risque (déjà bon → rien ; pointe ailleurs → re-pointe).
# `claude` absent du PATH → avertit et sort en 0 (ne casse pas le déploiement).
# Le binaire du CLI est ${CLAUDE_BIN:-claude} (surchargeable pour les tests).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MCP_BIN="$REPO_ROOT/bin/google-mcp"
SERVER_NAME="google-multi-account"
GWSA_CLIENT="claude-code"
BROKER_PORT="4878"
SCOPE="user"
CLAUDE="${CLAUDE_BIN:-claude}"

# ── affichage (même convention que install-claude-desktop.sh) ────
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print|--dry-run) DRY=1 ;;
    --name) shift; SERVER_NAME="${1:-}" ;;
    --name=*) SERVER_NAME="${1#*=}" ;;
    --port) shift; BROKER_PORT="${1:-}" ;;
    --port=*) BROKER_PORT="${1#*=}" ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "argument inconnu : $1 (voir --help)" ;;
  esac
  shift
done
[[ -n "$SERVER_NAME" ]] || die "--name vide"
[[ "$BROKER_PORT" =~ ^[0-9]+$ ]] && [[ "$BROKER_PORT" -ge 1024 && "$BROKER_PORT" -le 65535 ]] \
  || die "--port doit être un entier entre 1024 et 65535 (reçu : « $BROKER_PORT »)"

# ── pré-requis : le binaire MCP existe et est exécutable ─────────
[[ -x "$MCP_BIN" ]] || die "binaire MCP absent ou non exécutable : $MCP_BIN"

# Version réellement branchée (fichier VERSION à côté du binaire en copie déployée).
MCP_VERSION="dev"
[[ -s "$REPO_ROOT/VERSION" ]] && MCP_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"

step "Branchement de « $SERVER_NAME » dans Claude Code"
echo "  binaire  : $MCP_BIN"
echo "  version  : $MCP_VERSION"
echo "  broker   : port $BROKER_PORT"
echo "  scope    : $SCOPE (visible depuis n'importe quel dossier)"

# La commande d'enregistrement, construite une fois (réutilisée en dry-run et réel).
add_cmd=("$CLAUDE" mcp add "$SERVER_NAME" --scope "$SCOPE"
         --env "GWSA_CLIENT=$GWSA_CLIENT" --env "GWSA_BROKER_PORT=$BROKER_PORT"
         -- "$MCP_BIN")

# ── dry-run : montrer la commande, ne rien exécuter ──────────────
if [[ -n "$DRY" ]]; then
  warn "Dry-run (--print) : aucune écriture. Commande qui SERAIT lancée :"
  printf '  '; printf '%q ' "${add_cmd[@]}"; echo
  exit 0
fi

# ── dégradation gracieuse : CLI claude absent ────────────────────
if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  warn "CLI « $CLAUDE » introuvable dans le PATH — Claude Code non branché."
  echo "  Installe Claude Code, puis relance ce script, ou enregistre à la main :"
  printf '  '; printf '%q ' "${add_cmd[@]}"; echo
  exit 0
fi

# ── idempotence : que pointe l'entrée existante ? ────────────────
# `claude mcp get <name>` sort en 0 si l'entrée existe ; sa sortie cite le
# `command`. Si c'est déjà le bon binaire → rien. Sinon → re-pointer.
set +e
current="$("$CLAUDE" mcp get "$SERVER_NAME" 2>&1)"
get_rc=$?
set -e

if [[ "$get_rc" -eq 0 ]]; then
  if grep -qF "$MCP_BIN" <<<"$current"; then
    ok "Déjà branché sur $MCP_BIN — rien à faire."
    exit 0
  fi
  warn "Entrée « $SERVER_NAME » présente mais pointe ailleurs — re-branchement."
  "$CLAUDE" mcp remove "$SERVER_NAME" --scope "$SCOPE" >/dev/null 2>&1 \
    || "$CLAUDE" mcp remove "$SERVER_NAME" >/dev/null 2>&1 \
    || warn "retrait de l'ancienne entrée en échec — « $CLAUDE mcp add » va tenter d'écraser"
fi

# ── enregistrement ───────────────────────────────────────────────
if "${add_cmd[@]}" >/dev/null 2>&1; then
  ok "Entrée « $SERVER_NAME » enregistrée (scope $SCOPE, GWSA_CLIENT=$GWSA_CLIENT)."
  echo
  echo "${B}→ Ouvre un nouveau « claude »${N} — « /mcp » doit lister « $SERVER_NAME »."
  echo "  Vérifier : claude mcp get $SERVER_NAME"
else
  die "« $CLAUDE mcp add » a échoué — relance à la main :$(printf ' %q' "${add_cmd[@]}")"
fi
