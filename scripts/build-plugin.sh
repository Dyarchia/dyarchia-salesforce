#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${SOURCE_ROOT:-skills}"
OUTPUT_ROOT="${OUTPUT_ROOT:-dist}"
PLUGIN_NAME="${PLUGIN_NAME:-dyarchia-salesforce}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$REPO_ROOT/$SOURCE_ROOT"
OUTPUT_DIR="$REPO_ROOT/$OUTPUT_ROOT"
MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"

if ! command -v zip >/dev/null 2>&1; then
    echo "zip is not on PATH. Use scripts/build-plugin.ps1 instead." >&2
    exit 1
fi

[ -d "$SOURCE_DIR" ] || { echo "Source root not found: $SOURCE_DIR" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "Host manifest not found: $MANIFEST" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"

DEST="$OUTPUT_DIR/$PLUGIN_NAME.plugin"
rm -f "$DEST"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for dir in .claude-plugin .codex-plugin "$SOURCE_ROOT"; do
    [ -d "$REPO_ROOT/$dir" ] || continue
    mkdir -p "$STAGE/$(dirname "$dir")"
    cp -R "$REPO_ROOT/$dir" "$STAGE/$dir"
done

for leaf in README.md LICENSE; do
    [ -f "$REPO_ROOT/$leaf" ] && cp "$REPO_ROOT/$leaf" "$STAGE/$leaf"
done

find "$STAGE" -exec touch -t 198001010000 {} +

( cd "$STAGE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -qX9 "$DEST" -@ )

printf 'Built %s.plugin - %s file(s), %s bytes\n' \
    "$PLUGIN_NAME" "$(unzip -l "$DEST" | tail -1 | awk '{print $2}')" "$(wc -c < "$DEST")"
printf '  %s\n' "$DEST"
