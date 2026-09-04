#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${SOURCE_ROOT:-skills}"
SHARED_ROOT="${SHARED_ROOT:-references-shared}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/$SOURCE_ROOT"
SHARED_DIR="$REPO_ROOT/$SHARED_ROOT"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "error: source root not found: $SOURCE_DIR" >&2
    exit 1
fi
if [ ! -d "$SHARED_DIR" ]; then
    echo "error: shared root not found: $SHARED_DIR" >&2
    exit 1
fi

read_manifest() {
    local path="$1"
    [ -f "$path" ] || return 0
    sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$path" |
        grep -v '^#' | grep -v '^$' |
        sed -e 's/\.md$//' -e 's/$/.md/' |
        LC_ALL=C sort -u
}

sync_one() {
    local name="$1"
    local src="$SOURCE_DIR/$name"
    local target="$src/references/shared"

    if [ ! -d "$src" ]; then
        echo "error: skill folder not found: $src" >&2
        return 1
    fi

    local manifest
    manifest="$(read_manifest "$src/shared-refs.txt")"

    if [ -z "$manifest" ]; then
        rm -rf "$target"
        return 0
    fi

    mkdir -p "$target"

    local fragment
    while IFS= read -r fragment; do
        if [ ! -f "$SHARED_DIR/$fragment" ]; then
            echo "error: $name : shared-refs.txt declares '$fragment', which is not in $SHARED_ROOT" >&2
            return 1
        fi
        cp -f "$SHARED_DIR/$fragment" "$target/$fragment"
    done <<< "$manifest"

    local existing pruned=0
    while IFS= read -r existing; do
        [ -n "$existing" ] || continue
        if ! grep -qxF "$existing" <<< "$manifest"; then
            rm -f "$target/$existing"
            pruned=$((pruned + 1))
        fi
    done < <(find "$target" -maxdepth 1 -type f -printf '%f\n')

    local count
    count=$(grep -c . <<< "$manifest")
    printf '%-40s fragments=%-4s pruned=%s\n' "$name" "$count" "$pruned"
    TOTAL=$((TOTAL + count))
}

if [ "$#" -gt 0 ]; then
    targets=("$@")
else
    mapfile -t targets < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi

TOTAL=0
for name in "${targets[@]}"; do
    sync_one "$name"
done

echo "Synced $TOTAL shared fragment(s) across ${#targets[@]} skill(s)"
