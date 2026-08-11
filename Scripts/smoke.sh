#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="dist/KuromiCleans.app/Contents/MacOS/KuromiCleans"
if [ ! -x "$BIN" ]; then
    echo "App not built yet; building now."
    bash Scripts/build_app.sh
fi

echo "== Dry run against $HOME/Downloads (nothing will be moved) =="
if ! OUT="$("$BIN" --dry-run --path "$HOME/Downloads")"; then
    echo "Dry run failed." >&2
    exit 1
fi
echo "$OUT"

echo
echo "== Per-category counts =="
echo "$OUT" | awk -F ' -> ' '/ -> / { split($2, parts, "/"); counts[parts[1]]++; n++ } END { if (n == 0) print "(nothing to move)"; for (c in counts) print c ": " counts[c] }'

echo
echo "== Skipped items =="
SKIPPED="$(echo "$OUT" | grep '^skip: ' | sed 's/^skip: //')"
if [ -n "$SKIPPED" ]; then
    echo "$SKIPPED"
else
    echo "(none)"
fi
