#!/usr/bin/env bash
# bootstrap.sh — installe les outils ET provisionne GCP en un seul geste (macOS).
#
# Pour une machine neuve. À LANCER DEPUIS UN CLONE du dépôt (git clone … puis
# ./scripts/bootstrap.sh) — PAS en « curl | bash » comme install.sh : ce script
# lit ses scripts frères via son propre chemin. Enchaîne :
#   1. Xcode Command Line Tools (Swift → Touch ID / Secure Enclave)
#   2. serveur MCP « mag » sur le PATH (via install.sh, release figée)
#   3. provisioning GCP (scripts/provision-gcp.sh — installe gcloud tout seul)
#
# macOS uniquement : le modèle de sécurité (clé maître au Keychain, Touch ID via
# Secure Enclave, navigateur hôte pour OAuth) n'existe pas en conteneur Linux —
# d'où l'absence de variante Docker.
#
# Les arguments sont transmis tels quels à provision-gcp.sh, par ex. :
#   ./scripts/bootstrap.sh --confirm-account moi@gmail.com   # provisioning non interactif
#
# Idempotent : chaque étape détecte l'existant et ne refait rien d'inutile.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_URL="https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh"

if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

usage() {
  cat <<'EOF'
bootstrap.sh — installe les outils et provisionne GCP en un geste (macOS).

  ./scripts/bootstrap.sh [args provision-gcp.sh…]

À lancer depuis un clone du dépôt (pas en curl | bash).
Enchaîne : Xcode CLT → serveur MCP « mag » → provisioning GCP.
Les arguments sont passés à provision-gcp.sh (ex. --confirm-account moi@gmail.com).
Ensuite, dans un nouveau terminal : « mag add <alias> » pour connecter tes comptes.
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

[[ "$(uname)" == "Darwin" ]] || die "macOS requis (Keychain + Touch ID + Secure Enclave). Pas de variante Docker — voir l'en-tête."

# ── 1. Xcode Command Line Tools ──────────────────────────────────
step "1/3 · Xcode Command Line Tools (Swift → Touch ID)"
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode CLT présents"
else
  warn "absents — ouverture de l'installateur système…"
  xcode-select --install 2>/dev/null || true
  if [[ -t 0 ]]; then
    echo "→ Termine l'installation dans la fenêtre qui s'ouvre (quelques minutes)."
    read -r -p "   Appuie sur Entrée une fois l'installation finie… " _ || true
  fi
  xcode-select -p >/dev/null 2>&1 || die "Xcode CLT toujours absents — relance ce script une fois l'installation terminée."
fi

# ── 2. Serveur MCP (« mag » sur le PATH) ─────────────────────────
step "2/3 · Serveur MCP (mag)"
if command -v mag >/dev/null 2>&1; then
  ok "mag déjà sur le PATH ($(command -v mag)) — rien à installer"
elif [[ -x "$REPO_ROOT/install.sh" ]]; then
  bash "$REPO_ROOT/install.sh"
else
  warn "install.sh introuvable localement — installation depuis GitHub."
  curl -fsSL "$INSTALL_URL" | bash
fi

# ── 3. Provisioning GCP ──────────────────────────────────────────
# provision-gcp.sh installe gcloud lui-même (étape 1/7) ; inutile de le faire ici.
step "3/3 · Provisioning GCP"
PROVISION="$REPO_ROOT/scripts/provision-gcp.sh"
[[ -x "$PROVISION" ]] || die "provision-gcp.sh introuvable ($PROVISION) — lance bootstrap depuis un clone du dépôt, pas en curl | bash."
exec "$PROVISION" "$@"
