#!/usr/bin/env bash
# set-github-metadata.sh — aligner les métadonnées GitHub du dépôt sur le
# positionnement produit : multi-account · policy default-deny · human-in-the-loop
# · local-first. Fiche 0071.
#
# Geste HUMAIN et SORTANT : modifie la description, la homepage et les topics du
# dépôt PUBLIC via « gh ». Le LLM ne le lance JAMAIS lui-même (doctrine CLAUDE.md :
# aucune action irréversible/sortante sans geste humain). Il peut proposer la
# commande ; c'est toi qui l'exécutes.
#
# Source de vérité versionnée des métadonnées : ce fichier. Idempotent — le
# relancer réaligne le dépôt sur ces valeurs.
#
# Usage :
#   ./scripts/set-github-metadata.sh --dry-run   # affiche ce qui serait posé, sans « gh »
#   ./scripts/set-github-metadata.sh             # applique (nécessite « gh » authentifié)
#
# La homepage pointe la doc en ligne (fiche 0072) : à poser une fois le site
# publié sur https://docs.elzinko.fr (sinon, mets l'URL du dépôt en attendant).
set -euo pipefail

REPO="${GWSA_REPO:-elzinko/google-mcp-multi-account}"
DESC="Multi-account Google Workspace (Gmail, Drive) for LLM agents — 100% local, default-deny policy, human-in-the-loop access. A macOS MCP server."
HOMEPAGE="${GWSA_HOMEPAGE:-https://docs.elzinko.fr}"
# Positionnement : protocole, clients, services, multi-compte, sécurité/local, plateforme.
TOPICS=(
  mcp model-context-protocol claude claude-desktop cursor
  google-workspace gmail google-drive multi-account oauth
  local-first privacy human-in-the-loop least-privilege
  macos llm-tools ai-agents
)

DRY=""
case "${1:-}" in
  --dry-run|--print) DRY=1 ;;
  "" ) ;;
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "argument inconnu « $1 » (voir --help)" >&2; exit 2 ;;
esac

echo "Dépôt       : $REPO"
echo "Description : $DESC"
echo "Homepage    : $HOMEPAGE"
echo "Topics (${#TOPICS[@]}) : ${TOPICS[*]}"

if [[ -n "$DRY" ]]; then
  echo
  echo "(dry-run — rien n'est envoyé ; « gh » non requis)"
  echo "appliquerait : gh repo edit + gh api PUT repos/$REPO/topics"
  exit 0
fi

command -v gh >/dev/null 2>&1 \
  || { echo "✗ « gh » (GitHub CLI) requis et authentifié — https://cli.github.com" >&2; exit 1; }

echo
echo "→ description + homepage…"
gh repo edit "$REPO" --description "$DESC" --homepage "$HOMEPAGE"

# Topics : l'API « PUT /topics » REMPLACE l'ensemble (atomique) — évite d'empiler
# d'anciens topics, contrairement à « gh repo edit --add-topic » (ajout seul).
echo "→ topics (remplacement de l'ensemble)…"
api_args=()
for t in "${TOPICS[@]}"; do api_args+=(-f "names[]=$t"); done
gh api -X PUT "repos/$REPO/topics" -H "Accept: application/vnd.github+json" "${api_args[@]}" >/dev/null

echo "✓ métadonnées GitHub alignées ($REPO)."
