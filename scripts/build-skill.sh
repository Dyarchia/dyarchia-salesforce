#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${SOURCE_ROOT:-skills}"
OUTPUT_ROOT="${OUTPUT_ROOT:-dist}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/$SOURCE_ROOT"
OUTPUT_DIR="$REPO_ROOT/$OUTPUT_ROOT"
ZIP_EPOCH="198001010000"

if ! command -v zip >/dev/null 2>&1; then
    echo "error: 'zip' is required and not on PATH" >&2
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "error: source root not found: $SOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

build_one() {
    local name="$1"
    local src="$SOURCE_DIR/$name"
    local dest="$OUTPUT_DIR/$name.skill"

    if [ ! -d "$src" ]; then
        echo "error: skill folder not found: $src" >&2
        return 1
    fi
    if [ ! -f "$src/SKILL.md" ]; then
        echo "error: skill folder has no SKILL.md: $src" >&2
        return 1
    fi

    rm -f "$dest"

    local stage
    stage="$(mktemp -d)"
    cp -R "$src" "$stage/$name"
    find "$stage/$name" -exec touch -t "$ZIP_EPOCH" {} +
    (cd "$stage" && find "$name" -type f | LC_ALL=C sort | TZ=UTC zip -qX "$dest" -@)
    rm -rf "$stage"

    local files bytes
    files=$(find "$src" -type f | wc -l | tr -d ' ')
    bytes=$(wc -c < "$dest" | tr -d ' ')
    printf '%-40s files=%-4s bytes=%s\n' "$name" "$files" "$bytes"
}

if [ "$#" -gt 0 ]; then
    targets=("$@")
else
    mapfile -t targets < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi

for name in "${targets[@]}"; do
    build_one "$name"
done

echo "Built ${#targets[@]} bundle(s) into $OUTPUT_DIR"
