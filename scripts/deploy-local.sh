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
#   ./scripts/deploy-local.sh --tag v0.2.0   # déploie CE tag, quel que soit HEAD
#   ./scripts/deploy-local.sh --print        # dry-run : dit ce qu'il ferait, n'écrit rien
#   ./scripts/deploy-local.sh --list         # versions déployées (* = courante)
#   ./scripts/deploy-local.sh --rollback X   # rebascule current sur la version X
#   ./scripts/deploy-local.sh --github v0.2.0 # …depuis le tarball GitHub, sans clone (fiche 0020)
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
# Source « GitHub sans clone » (fiche 0020) — sourcée à la demande dans --github.
LIB_GH="$(cd "$(dirname "$0")" && pwd)/lib-github-release.sh"

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
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "argument inconnu « $1 » (voir --help)" ;;
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

point_current_at() { # point_current_at <version> — bascule atomique du symlink
  ln -sfn "$DEPLOY_ROOT/$1" "$CURRENT_LINK"
}

stop_broker() { # recycle le broker du couloir stable, sinon l'ancien code reste servi
  local mag="$CURRENT_LINK/bin/mag"
  [[ -x "$mag" ]] || { warn "mag introuvable dans la version déployée — broker non recyclé"; return 0; }
  "$mag" broker stop || warn "arrêt du broker en échec — le relancer à la main si besoin"
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
SOURCE_REF=""
if [[ "$SOURCE_TYPE" == "github" ]]; then
  # Chemin « sans clone » (fiche 0020) : on ne fige pas une référence git locale
  # mais le tarball que GitHub publie pour le tag demandé.
  [[ -n "$GH_TAG" ]] || die "usage : --github <tag> (ex. --github v0.2.0)"
  command -v curl >/dev/null 2>&1 || die "curl est requis pour --github"
  [[ -f "$LIB_GH" ]] || die "lib introuvable : $LIB_GH"
  # shellcheck source=scripts/lib-github-release.sh
  source "$LIB_GH"
  VERSION="$GH_TAG"
  ok "version : $VERSION (release GitHub $(gh_repo) — sans clone)"
else
  command -v git >/dev/null 2>&1 || die "git est requis"
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$REPO_ROOT n'est pas un dépôt git"

  if [[ -n "$WANT_TAG" ]]; then
    # --tag archive une référence git, jamais l'arbre de travail : on peut donc
    # installer une version pendant qu'on développe autre chose à côté.
    git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$WANT_TAG" >/dev/null \
      || die "tag « $WANT_TAG » inconnu dans $REPO_ROOT (git tag pour la liste ; git fetch --tags si besoin)"
    VERSION="$WANT_TAG"
    SOURCE_REF="refs/tags/$WANT_TAG"
    ok "version : $VERSION (tag demandé — arbre de travail ignoré)"
  else
    [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
      || die "arbre de travail sale — commite ou remise tes modifications avant de déployer"
    ok "arbre de travail propre"

    VERSION="$(git -C "$REPO_ROOT" describe --exact-match --tags HEAD 2>/dev/null || true)"
    [[ -n "$VERSION" ]] \
      || die "HEAD n'est pas taggé — pose un tag d'abord (ex. : git tag v0.2.0), sinon la version déployée n'est pas identifiable"
    SOURCE_REF="HEAD"
    ok "version : $VERSION"
  fi
fi

TARGET="$DEPLOY_ROOT/$VERSION"

if [[ -n "$DRY" ]]; then
  step "Dry-run"
  echo "déploierait   : $VERSION"
  echo "source        : $([[ "$SOURCE_TYPE" == "github" ]] && echo "tarball GitHub $(gh_repo)" || echo "git archive ${SOURCE_REF}")"
  echo "vers          : $TARGET"
  echo "current →     : $TARGET"
  if [[ -d "$TARGET" ]]; then warn "déjà déployé — seul le symlink current serait rebasculé"; fi
  echo "puis          : arrêt du broker + geste humain (brancher Claude Desktop)"
  exit 0
fi

step "Déploiement"
mkdir -p "$DEPLOY_ROOT"
if [[ -d "$TARGET" ]]; then
  # Cible RÉUTILISÉE : valider avant de basculer (revue Codex, cibles réutilisées).
  if [[ "$SOURCE_TYPE" == "github" ]]; then
    # (a) une version legacy (ancien deploy clone) n'a pas d'updater sans clone —
    #     ne jamais y basculer current/mag, sinon « mag update » redeviendrait
    #     dépendant d'un clone (P1).
    [[ -f "$TARGET/scripts/lib-github-release.sh" ]] \
      || die "$VERSION déjà déployé mais antérieur à l'update sans clone — current n'est pas basculé dessus (supprime « $TARGET » ou passe par un clone)"
    # (b) collision de tag ENTRE DÉPÔTS : ne pas réutiliser un dossier venu d'un
    #     autre repo (son .origin diffère), sinon current basculerait sur le code
    #     d'un autre dépôt et les updates suivants viseraient la mauvaise source (P2).
    [[ "$(cat "$TARGET/.origin" 2>/dev/null)" == "github:$(gh_repo)" ]] \
      || die "$VERSION déjà déployé depuis un autre dépôt (.origin ≠ github:$(gh_repo)) — supprime « $TARGET » ou choisis un GWSA_DEPLOY_ROOT distinct"
  else
    # Mode clone : même risque de collision de tag entre dépôts (ex. dossier posé
    # depuis upstream, puis --tag depuis un fork). Si la provenance du dossier
    # diffère du remote de CE clone, ne pas le réutiliser (revue Codex). On ne
    # refuse que quand les deux provenances sont connues et diffèrent.
    _want="$(clone_github_origin "$REPO_ROOT")"; _have="$(cat "$TARGET/.origin" 2>/dev/null || true)"
    [[ -z "$_want" || -z "$_have" || "$_have" == "$_want" ]] \
      || die "$VERSION déjà déployé depuis un autre dépôt ($_have ≠ $_want) — supprime « $TARGET » ou choisis un GWSA_DEPLOY_ROOT distinct"
  fi
  ok "$VERSION déjà déployé — pas de réécriture"
else
  tmp="$(mktemp -d "$DEPLOY_ROOT/.tmp-XXXXXX")"
  if [[ "$SOURCE_TYPE" == "github" ]]; then
    gh_download_version "$VERSION" "$tmp" \
      || { rm -rf "$tmp"; die "téléchargement/extraction du tarball $VERSION en échec (GitHub joignable ? tag existant ?)"; }
    # Garde-fou (revue Codex P1) : ne jamais basculer « current » — donc le mag
    # du PATH — sur une version ANTÉRIEURE à l'update sans clone. Son update.sh
    # exigerait un clone (.git/.source), et tout « mag update » suivant mourrait.
    [[ -f "$tmp/scripts/lib-github-release.sh" ]] \
      || { rm -rf "$tmp"; die "$VERSION est antérieure à l'update sans clone (aucun updater intégré) — installe-la depuis un clone si tu y tiens"; }
    # Marqueur d'origine : update.sh sait qu'il doit re-tirer depuis GitHub, pas
    # depuis un clone. Pas de .source — il n'y a pas de clone (fiche 0020).
    printf '%s\n' "github:$(gh_repo)" > "$tmp/.origin"
  else
    # git archive n'exporte que les fichiers SUIVIS de HEAD : pas de .git/, pas de
    # worktrees, aucun fichier non commité. C'est ce qui garantit la copie figée.
    git -C "$REPO_ROOT" archive "$SOURCE_REF" | tar -x -C "$tmp" \
      || { rm -rf "$tmp"; die "échec de l'export git archive"; }
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
