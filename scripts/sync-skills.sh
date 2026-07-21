#!/usr/bin/env bash
# Synchronise les agent skills officiels du repo googleworkspace/cli
# vers .claude/skills/ (sous-ensemble utile à ce projet).
# Relancer après une mise à jour de gws : ./scripts/sync-skills.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SKILLS=(
  gws-shared
  gws-gmail gws-gmail-read gws-gmail-send gws-gmail-reply gws-gmail-reply-all
  gws-gmail-forward gws-gmail-triage
  gws-drive gws-drive-upload
  gws-calendar gws-calendar-agenda gws-calendar-insert
  gws-docs gws-docs-write
  gws-sheets gws-sheets-read gws-sheets-append
  gws-tasks gws-people
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --depth 1 https://github.com/googleworkspace/cli.git "$TMP/cli"

mkdir -p .claude/skills
for s in "${SKILLS[@]}"; do
  rm -rf ".claude/skills/$s"
  cp -R "$TMP/cli/skills/$s" ".claude/skills/$s"
done
echo "✓ ${#SKILLS[@]} skills synchronisés dans .claude/skills/"
