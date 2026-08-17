#!/usr/bin/env bash
# Alias déprécié — utilise scripts/sandbox.sh (ou : mag sandbox …).
echo "⚠ scripts/couloir.sh est déprécié — utilise scripts/sandbox.sh (ou mag sandbox)." >&2
exec "$(cd "$(dirname "$0")" && pwd)/sandbox.sh" "$@"
