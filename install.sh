#!/usr/bin/env bash
# install.sh — installer google-multi-account SANS cloner le dépôt (fiche 0020).
#
#   curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
#
# Ce que ça fait : télécharge la dernière version publiée depuis GitHub, la fige
# dans ~/.local/share/google-mcp/<tag>/, pose « current » dessus, met « gma » (+ alias « gwsa »)
# sur le PATH, branche Claude Desktop + Code, puis AFFICHE les étapes OAuth/GCP
# restantes — jamais exécutées à ta place (doctrine CLAUDE.md).
#
# Autonome par nature (lancé par « curl | bash », sans clone) : il duplique la
# logique minimale de scripts/lib-github-release.sh — garder les deux alignés.
#
# Surcharges (tests / cas particuliers) :
#   GWSA_REPO / GWSA_TAGS_URL / GWSA_TARBALL_BASE  (idem lib-github-release.sh)
#   GWSA_DEPLOY_ROOT   où figer les versions (défaut ~/.local/share/google-mcp)
#   GWSA_CLI_LINK      lien « gwsa » sur le PATH (défaut : brew, sinon ~/.local/bin)
#   GWSA_SKIP_WIRE=1   installe le serveur sans brancher Desktop/Code
set -euo pipefail

REPO="${GWSA_REPO:-elzinko/google-mcp-multi-account}"
DEPLOY_ROOT="${GWSA_DEPLOY_ROOT:-$HOME/.local/share/google-mcp}"
CURRENT_LINK="$DEPLOY_ROOT/current"

if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ── prérequis ────────────────────────────────────────────────────
step "Prérequis"
[[ "$(uname -s)" == "Darwin" ]] || warn "prévu pour macOS Apple Silicon — je continue quand même"
for tool in curl tar python3; do
  command -v "$tool" >/dev/null 2>&1 || die "« $tool » est requis"
done
GWS_MISSING=""
command -v gws >/dev/null 2>&1 \
  || { GWS_MISSING=1; warn "la CLI « gws » manque — installe-la : brew install googleworkspace-cli (rappelé à la fin)"; }

# ── dernière version publiée ─────────────────────────────────────
step "Dernière version publiée"
tags_url="${GWSA_TAGS_URL:-https://api.github.com/repos/$REPO/tags}"
# `|| true` : sous set -euo pipefail, un curl injoignable OU un grep sans
# correspondance fait échouer le pipe et avorterait AVANT le die explicite
# (curl silencieux → « curl | bash » s'arrête sans message). Revue Codex P2.
LATEST="$(curl -fsSL "$tags_url" 2>/dev/null \
  | grep -oE '"v[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sed 's/^v//' \
  | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" || true
[[ -n "$LATEST" ]] || die "impossible de lire la dernière version depuis GitHub ($tags_url) — réseau ? dépôt ?"
LATEST="v$LATEST"
ok "version : $LATEST"

TARGET="$DEPLOY_ROOT/$LATEST"

# ── télécharger + figer + basculer current ───────────────────────
step "Installation"
if [[ -d "$TARGET" ]]; then
  # Cible RÉUTILISÉE : valider avant de basculer (revue Codex).
  # (a) une version legacy pré-existante (ancien deploy clone) n'a pas d'updater
  #     sans clone → n'y bascule jamais current/gwsa (P1).
  [[ -f "$TARGET/scripts/lib-github-release.sh" ]] \
    || die "$LATEST déjà présent mais antérieur à l'update sans clone — supprime « $TARGET » ou installe depuis un clone"
  # (b) collision de tag entre dépôts : ne pas réutiliser un dossier venu d'un
  #     autre repo (.origin différent), sinon current basculerait sur le code
  #     d'un autre dépôt (P2, réutilisation cross-repo).
  [[ "$(cat "$TARGET/.origin" 2>/dev/null)" == "github:$REPO" ]] \
    || die "$LATEST déjà présent mais installé depuis un autre dépôt (.origin ≠ github:$REPO) — supprime « $TARGET » ou change GWSA_DEPLOY_ROOT"
  ok "$LATEST déjà présent — pas de re-téléchargement"
else
  base="${GWSA_TARBALL_BASE:-https://github.com/$REPO/archive/refs/tags}"
  url="$base/$LATEST.tar.gz"
  mkdir -p "$DEPLOY_ROOT"
  tmp="$(mktemp -d "$DEPLOY_ROOT/.tmp-XXXXXX")"
  # --strip-components=1 : le tarball GitHub a un dossier racine « <repo>-<tag>/ ».
  curl -fsSL "$url" | tar -xz -C "$tmp" --strip-components=1 \
    || { rm -rf "$tmp"; die "téléchargement/extraction de $LATEST en échec ($url)"; }
  # Garde-fou (revue Codex P1) : ne pas installer une version antérieure à
  # l'update sans clone — son « gma update » exigerait un clone et mourrait.
  [[ -f "$tmp/scripts/lib-github-release.sh" ]] \
    || { rm -rf "$tmp"; die "$LATEST est antérieure à l'update sans clone — attends la prochaine release, ou installe depuis un clone"; }
  printf '%s\n' "$LATEST" > "$tmp/VERSION"
  # Marqueur d'origine : « gma update » saura re-tirer depuis GitHub (pas de clone).
  printf '%s\n' "github:$REPO" > "$tmp/.origin"
  mv "$tmp" "$TARGET"
  ok "copie figée : $TARGET"
fi
ln -sfn "$TARGET" "$CURRENT_LINK"
ok "current → $LATEST"

# Recycler le broker : un broker déjà lancé continue de servir l'ANCIEN code
# après un ré-install (comme update/deploy-local — revue Codex). Best-effort :
# à la première install il n'y a pas de broker, c'est sans effet.
if [[ -x "$CURRENT_LINK/bin/gwsa" ]]; then
  "$CURRENT_LINK/bin/gwsa" broker stop >/dev/null 2>&1 || true
fi

# ── gwsa sur le PATH ─────────────────────────────────────────────
step "Commandes sur le PATH — gma (+ alias gwsa)"
link="${GWSA_CLI_LINK:-}"
if [[ -z "$link" ]]; then
  if command -v brew >/dev/null 2>&1; then link="$(brew --prefix)/bin/gwsa"; else link="$HOME/.local/bin/gwsa"; fi
fi
mkdir -p "$(dirname "$link")"
ln -sfn "$CURRENT_LINK/bin/gwsa" "$link"
ok "gwsa → $link"
# Alias « gma » (nom aligné sur le connecteur google-multi-account). « gwsa »
# reste disponible comme alias déprécié.
gma_link="$(dirname "$link")/gma"
ln -sfn "$CURRENT_LINK/bin/gma" "$gma_link"
ok "gma → $gma_link"
case ":$PATH:" in
  *":$(dirname "$link"):"*) ;;
  *) warn "« $(dirname "$link") » n'est pas dans ton PATH — ajoute-le pour utiliser « gma »";;
esac

# ── brancher les clients LLM ─────────────────────────────────────
if [[ -z "${GWSA_SKIP_WIRE:-}" ]]; then
  step "Branchement des clients"
  DESK="$CURRENT_LINK/scripts/install-claude-desktop.sh"
  CODE="$CURRENT_LINK/scripts/install-claude-code.sh"
  if [[ -x "$DESK" ]]; then
    if [[ -n "${GWSA_DESKTOP_CONFIG:-}" ]]; then
      "$DESK" --config "$GWSA_DESKTOP_CONFIG" >/dev/null 2>&1 \
        && ok "Claude Desktop branché" || warn "branchement Desktop à faire : $DESK"
    else
      "$DESK" >/dev/null 2>&1 && ok "Claude Desktop branché" || warn "branchement Desktop à faire : $DESK"
    fi
  fi
  if command -v claude >/dev/null 2>&1 && [[ -x "$CODE" ]]; then
    "$CODE" >/dev/null 2>&1 && ok "Claude Code (CLI) branché" || warn "branchement Claude Code à faire : $CODE"
  fi
fi

# ── ce qui reste à l'humain : le setup Google ────────────────────
step "Il reste le setup Google — à toi (une fois)"
if [[ -n "$GWS_MISSING" ]]; then
  cat <<EOF
${R}0) D'ABORD installer la CLI Google « gws » — sinon l'étape 2 échouera :${N}
     brew install googleworkspace-cli

EOF
fi
cat <<EOF
1) Projet Google Cloud + OAuth (≈10 min) :
     $CURRENT_LINK/scripts/provision-gcp.sh
   Détail : https://github.com/$REPO/blob/main/docs/setup-oauth.md
2) Connecter un compte (l'email désigne le compte) :
     gma add perso votre.email@gmail.com
3) Redémarrer Claude Desktop (Cmd-Q), puis demander à l'agent :
     « fais le point sur mon setup Google »
   Il lit l'état et propose la commande de chaque étape manquante — tu l'exécutes.

Mettre à jour plus tard, sans clone : « gma update ».
Le serveur doit annoncer « $LATEST ».
EOF
