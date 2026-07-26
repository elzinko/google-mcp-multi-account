#!/usr/bin/env bash
# release.sh — publier une version : calcule le semver, écrit le CHANGELOG, tague, pousse.
#
# Le tag reste la source de vérité de la version (fiche 0023) ; ce script ne fait
# que le calculer et le poser proprement, avec les garde-fous qui manquaient.
#
# Usage :
#   ./scripts/release.sh              # niveau déduit des conventional commits
#   ./scripts/release.sh patch        # …ou forcé
#   ./scripts/release.sh minor
#   ./scripts/release.sh major
#   ./scripts/release.sh --print      # dry-run : dit ce qui sortirait, n'écrit rien
#
# Déduction : un « BREAKING CHANGE » ou un « type!: » → major ; un « feat » →
# minor ; sinon patch. Semver standard, y compris en 0.x.
#
# Refuse : arbre sale, branche autre que main, retard sur origin/main, tag déjà
# posé, aucun commit depuis le dernier tag, tests rouges.
# Ensuite : ./scripts/update.sh pour installer la version sur ce poste.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_BRANCH="${GWSA_MAIN_BRANCH:-main}"
TEST_CMD="${GWSA_RELEASE_TEST_CMD:-./scripts/test.sh}"

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
LEVEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print|--dry-run) DRY=1 ;;
    patch|minor|major) LEVEL="$1" ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "argument inconnu « $1 » (voir --help)" ;;
  esac
  shift
done

cd "$REPO_ROOT"

# ── contrôles ────────────────────────────────────────────────────
step "Contrôles"
command -v git >/dev/null 2>&1 || die "git est requis"
git rev-parse --git-dir >/dev/null 2>&1 || die "$REPO_ROOT n'est pas un dépôt git"

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "$MAIN_BRANCH" ]] \
  || die "publier se fait depuis « $MAIN_BRANCH » (tu es sur « $branch ») — merge d'abord"
ok "branche : $branch"

[[ -z "$(git status --porcelain)" ]] \
  || die "arbre de travail sale — commite ou remise tes modifications avant de publier"
ok "arbre de travail propre"

# Retard sur origin : publier un tag qui n'existe pas en amont produit une
# version que personne d'autre ne peut retrouver.
if git remote get-url origin >/dev/null 2>&1; then
  git fetch --quiet --tags origin "$MAIN_BRANCH" 2>/dev/null || warn "fetch origin impossible — contrôle de retard sauté"
  if git rev-parse -q --verify "refs/remotes/origin/$MAIN_BRANCH" >/dev/null; then
    behind="$(git rev-list --count "HEAD..origin/$MAIN_BRANCH" 2>/dev/null || echo 0)"
    [[ "$behind" == "0" ]] \
      || die "$behind commit(s) de retard sur origin/$MAIN_BRANCH — « git pull » d'abord"
    ok "à jour avec origin/$MAIN_BRANCH"
  fi
fi

# ── version courante et suivante ─────────────────────────────────
last_tag="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
if [[ -z "$last_tag" ]]; then
  cur_major=0; cur_minor=0; cur_patch=0
  range=""
  ok "aucun tag existant — première version"
else
  ver="${last_tag#v}"
  cur_major="${ver%%.*}"; rest="${ver#*.}"
  cur_minor="${rest%%.*}"; cur_patch="${rest#*.}"
  [[ "$cur_major$cur_minor$cur_patch" =~ ^[0-9]+$ ]] \
    || die "dernier tag « $last_tag » non semver — impossible d'en déduire le suivant"
  range="$last_tag..HEAD"
  ok "dernière version : $last_tag"
fi

if [[ -n "$range" ]]; then
  count="$(git rev-list --count "$range")"
  [[ "$count" != "0" ]] \
    || die "aucun commit depuis $last_tag — rien à publier"
else
  count="$(git rev-list --count HEAD)"
fi

# Niveau déduit des conventional commits, sauf si l'argument l'impose.
if [[ -z "$LEVEL" ]]; then
  body="$(git log ${range:+"$range"} --format='%s%n%b')"
  if echo "$body" | grep -qE '^BREAKING[ -]CHANGE|^[a-z]+(\([^)]*\))?!:'; then
    LEVEL="major"
  elif echo "$body" | grep -qE '^feat(\([^)]*\))?!?:'; then
    LEVEL="minor"
  else
    LEVEL="patch"
  fi
  ok "niveau déduit de $count commit(s) : $LEVEL"
else
  ok "niveau imposé : $LEVEL"
fi

case "$LEVEL" in
  major) NEXT="v$((cur_major + 1)).0.0" ;;
  minor) NEXT="v$cur_major.$((cur_minor + 1)).0" ;;
  patch) NEXT="v$cur_major.$cur_minor.$((cur_patch + 1))" ;;
esac

git rev-parse -q --verify "refs/tags/$NEXT" >/dev/null \
  && die "le tag $NEXT existe déjà — rien de publié"
ok "prochaine version : $NEXT"

# ── dry-run ──────────────────────────────────────────────────────
if [[ -n "$DRY" ]]; then
  step "Dry-run (--print) : rien n'est écrit ni poussé"
  echo "publierait : $NEXT ($LEVEL, $count commit(s) depuis ${last_tag:-le début})"
  echo "lancerait  : $TEST_CMD"
  echo "écrirait   : CHANGELOG.md + commit « chore(release): $NEXT » + tag annoté"
  echo "pousserait : $MAIN_BRANCH et $NEXT vers origin"
  exit 0
fi

# ── tests ────────────────────────────────────────────────────────
step "Tests"
$TEST_CMD >/dev/null 2>&1 \
  || die "« $TEST_CMD » est rouge — rien de publié. Relance-le pour voir les échecs."
ok "suite de tests verte"

# ── CHANGELOG ────────────────────────────────────────────────────
step "CHANGELOG"
tmp_notes="$(mktemp)"
trap 'rm -f "$tmp_notes"' EXIT

section() { # section <titre> <motif grep>
  local title="$1" pattern="$2" lines
  lines="$(git log ${range:+"$range"} --no-merges --format='%s' | grep -E "$pattern" || true)"
  [[ -n "$lines" ]] || return 0
  printf '### %s\n\n' "$title" >> "$tmp_notes"
  printf '%s\n' "$lines" | sed 's/^/- /' >> "$tmp_notes"
  printf '\n' >> "$tmp_notes"
}

printf '## %s — %s\n\n' "$NEXT" "$(date +%F)" > "$tmp_notes"
section "Fonctionnalités" '^feat(\([^)]*\))?!?:'
section "Corrections" '^fix(\([^)]*\))?!?:'
section "Documentation" '^docs(\([^)]*\))?!?:'
section "Autres" '^(refactor|perf|chore|test|build|ci)(\([^)]*\))?!?:'

CHANGELOG="$REPO_ROOT/CHANGELOG.md"
if [[ ! -f "$CHANGELOG" ]]; then
  printf '# Journal des versions\n\n' > "$CHANGELOG"
fi
# Insertion en tête de liste : la version la plus récente se lit en premier.
head_line="$(head -1 "$CHANGELOG")"
{
  printf '%s\n\n' "$head_line"
  cat "$tmp_notes"
  tail -n +2 "$CHANGELOG" | sed '1{/^$/d;}'
} > "$CHANGELOG.new"
mv "$CHANGELOG.new" "$CHANGELOG"
ok "CHANGELOG.md : section $NEXT ajoutée"

# ── commit, tag, push ────────────────────────────────────────────
step "Publication"
git add CHANGELOG.md
git commit --quiet -m "chore(release): $NEXT"
ok "commit chore(release): $NEXT"

git tag -a "$NEXT" -F - <<TAGMSG
$NEXT

$(tail -n +2 "$tmp_notes")
TAGMSG
ok "tag annoté $NEXT"

if git remote get-url origin >/dev/null 2>&1; then
  git push --quiet origin "$MAIN_BRANCH" || die "push de $MAIN_BRANCH en échec — le tag est posé localement"
  git push --quiet origin "$NEXT" || die "push du tag en échec — « git push origin $NEXT » à refaire"
  ok "poussé : $MAIN_BRANCH et $NEXT"
else
  warn "aucun remote « origin » — publication locale seulement"
fi

step "Installer cette version sur ce poste"
echo "  ./scripts/update.sh"
