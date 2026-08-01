#!/usr/bin/env bash
# lib-github-release.sh — récupérer une version PUBLIÉE depuis GitHub, sans clone.
#
# Pourquoi : jusqu'ici install et update exigeaient un clone git présent (tags
# lus dans le clone, `git archive` pour figer une version). Cette lib fournit le
# même résultat — « tag → dossier figé » — à partir du tarball que GitHub génère
# automatiquement pour chaque tag. Aucun artefact de release à produire, aucun
# clone requis. Cf. fiche 0020.
#
# Source unique partagée par scripts/update.sh et scripts/deploy-local.sh
# (--github). install.sh en réimplémente une copie MINIMALE : lancé par
# « curl … | bash », il n'a aucun clone d'où sourcer ce fichier — garder les deux
# alignés.
#
# Surcouches de test (hermétique, zéro réseau — voir scripts/test.sh) :
#   GWSA_REPO          owner/repo (défaut : elzinko/google-mcp-multi-account)
#   GWSA_TAGS_URL      URL JSON de la liste des tags (défaut : API GitHub) ;
#                      un test pointe un fichier file:// (curl sait le lire)
#   GWSA_TARBALL_BASE  base des tarballs par tag (défaut : github.com/<repo>/…) ;
#                      URL finale = "$GWSA_TARBALL_BASE/<tag>.tar.gz"

gh_repo() { printf '%s' "${GWSA_REPO:-elzinko/google-mcp-multi-account}"; }

gh_tags_url() {
  # per_page=100 : une seule requête couvre jusqu'à 100 tags (au lieu de 30 par
  # défaut) — donc « --to <vieux tag> » reste validable quand l'historique grossit.
  # Pagination complète (page 2+) différée : YAGNI tant que < 100 releases (Codex).
  printf '%s' "${GWSA_TAGS_URL:-https://api.github.com/repos/$(gh_repo)/tags?per_page=100}"
}

gh_tarball_url() { # $1=tag → URL du tarball de ce tag
  local base="${GWSA_TARBALL_BASE:-https://github.com/$(gh_repo)/archive/refs/tags}"
  printf '%s/%s.tar.gz' "$base" "$1"
}

# gh_latest_tag → imprime le dernier tag « vX.Y.Z » (tri semver décroissant).
# rc≠0 si GitHub est injoignable ou si aucun tag versionné n'existe.
# NB : l'API GitHub renvoie une page (~30 tags) — largement assez ici ; à
# paginer si le projet dépasse 30 versions (hors scope MVP, fiche 0020).
gh_latest_tag() {
  local latest
  # `|| latest=""` : sans ça, un grep sans correspondance (aucun tag) fait
  # échouer le pipe sous pipefail et, chez un appelant en `set -e`, avorte avant
  # le contrôle explicite ci-dessous.
  latest="$(gh_all_tags 2>/dev/null | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" || latest=""
  [[ -n "$latest" ]] || return 1
  printf 'v%s' "$latest"
}

# gh_all_tags → imprime tous les tags « vX.Y.Z » publiés (un par ligne).
# rc≠0 si GitHub est injoignable.
gh_all_tags() {
  local json
  json="$(curl -fsSL "$(gh_tags_url)" 2>/dev/null)" || return 1
  printf '%s' "$json" | grep -oE '"v[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -u
}

# gh_tag_exists <tag> → rc 0 si CE tag est publié sur GitHub (validation --to
# côté « sans clone », équivalent du `git rev-parse refs/tags` côté clone).
# rc≠0 aussi si GitHub est injoignable : on refuse un tag qu'on ne peut confirmer.
gh_tag_exists() {
  local want="$1"
  [[ -n "$want" ]] || return 2
  gh_all_tags 2>/dev/null | grep -qxF -- "$want"
}

# gh_download_version <tag> <dest_dir> — télécharge le tarball du tag et l'extrait
# dans dest_dir (créé au besoin). Le tarball GitHub porte un dossier racine
# « <repo>-<tag>/ » : --strip-components=1 l'enlève pour poser l'arbre à plat.
gh_download_version() {
  local tag="$1" dest="$2" url
  [[ -n "$tag" && -n "$dest" ]] || { echo "gh_download_version: tag et dest requis" >&2; return 2; }
  url="$(gh_tarball_url "$tag")"
  mkdir -p "$dest"
  # pipefail (posé par les appelants via `set -o pipefail`) fait remonter un
  # échec de curl OU de tar comme rc≠0 de la ligne.
  curl -fsSL "$url" | tar -xz -C "$dest" --strip-components=1
}
