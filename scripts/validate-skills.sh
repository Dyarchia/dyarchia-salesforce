#!/usr/bin/env bash
set -uo pipefail

SOURCE_ROOT="${SOURCE_ROOT:-skills}"
OUTPUT_ROOT="${OUTPUT_ROOT:-dist}"
SKILL_MD_WARN_BYTES="${SKILL_MD_WARN_BYTES:-20480}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/$SOURCE_ROOT"
OUTPUT_DIR="$REPO_ROOT/$OUTPUT_ROOT"
README="$REPO_ROOT/README.md"

INVOCATION_CLAUSE='Load only when the user explicitly invokes this skill by name'
NON_SKILL_TOKENS=" decimatio-salesforce decimatio-skill-authoring decimatio-dev "

errors=0
warnings=0

fail() { echo "FAIL  $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARN  $*" >&2; warnings=$((warnings + 1)); }

for tool in unzip sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: '$tool' is required and not on PATH" >&2
        exit 1
    fi
done

if [ ! -d "$SOURCE_DIR" ]; then
    echo "FAIL  source root not found: $SOURCE_DIR" >&2
    exit 1
fi

mapfile -t skills < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

if [ "${#skills[@]}" -eq 0 ]; then
    echo "FAIL  no skill folders under $SOURCE_DIR" >&2
    exit 1
fi

if [ ! -s "$README" ]; then
    fail "README.md is missing or empty"
fi

frontmatter_of() {
    awk 'NR == 1 && $0 != "---" { exit } NR == 1 { next } $0 == "---" { exit } { print }' "$1"
}

for name in "${skills[@]}"; do
    src="$SOURCE_DIR/$name"
    skill_md="$src/SKILL.md"

    if [ ! -f "$skill_md" ]; then
        fail "$name : no SKILL.md"
        continue
    fi

    fm="$(frontmatter_of "$skill_md")"
    if [ -z "$fm" ]; then
        fail "$name : SKILL.md has no YAML frontmatter block"
    else
        fm_name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*\(.*\)$/\1/p' | tr -d '\r' | head -1)"
        if [ -z "$fm_name" ]; then
            fail "$name : frontmatter has no 'name' key"
        elif [ "$fm_name" != "$name" ]; then
            fail "$name : frontmatter name '$fm_name' does not match folder"
        fi

        if ! printf '%s\n' "$fm" | grep -q '^description:'; then
            fail "$name : frontmatter has no 'description' key"
        elif ! printf '%s\n' "$fm" | grep -qF "$INVOCATION_CLAUSE"; then
            fail "$name : description is missing the explicit-invocation clause"
        fi
    fi

    md_bytes=$(wc -c < "$skill_md" | tr -d ' ')
    if [ "$md_bytes" -gt "$SKILL_MD_WARN_BYTES" ]; then
        warn "$name : SKILL.md is $md_bytes bytes (over $SKILL_MD_WARN_BYTES) - consider moving detail to references/"
    fi

    if [ -s "$README" ] && ! grep -qF "$name" "$README"; then
        fail "$name : not listed in README.md"
    fi

    bundle="$OUTPUT_DIR/$name.skill"
    if [ ! -f "$bundle" ]; then
        fail "$name : no bundle at $OUTPUT_ROOT/$name.skill"
        continue
    fi

    if unzip -Z1 "$bundle" | grep -q '\\'; then
        fail "$name : bundle has entries with backslashes - rebuild it"
    fi
    if unzip -Z1 "$bundle" | grep -qv "^$name/"; then
        fail "$name : bundle has entries not rooted at '$name/' - rebuild it"
    fi

    src_manifest="$(cd "$src" && find . -type f | sed "s|^\./|$name/|" | sort | while read -r rel; do
        printf '%s  %s\n' "$(sha256sum "$src/${rel#"$name/"}" | cut -d' ' -f1)" "$rel"
    done)"

    zip_manifest="$(unzip -Z1 "$bundle" | grep -v '/$' | sort | while read -r entry; do
        printf '%s  %s\n' "$(unzip -p "$bundle" "$entry" | sha256sum | cut -d' ' -f1)" "$entry"
    done)"

    if [ "$src_manifest" != "$zip_manifest" ]; then
        fail "$name : bundle is out of sync with source - rebuild it"
        diff <(printf '%s\n' "$src_manifest") <(printf '%s\n' "$zip_manifest") | sed 's/^/      /' >&2
    fi
done

if [ -s "$README" ]; then
    while read -r token; do
        [ -z "$token" ] && continue
        case " ${skills[*]} " in *" $token "*) continue ;; esac
        case "$NON_SKILL_TOKENS" in *" $token "*) continue ;; esac
        warn "README.md references '$token', which is not a skill folder"
    done < <(grep -oE 'decimatio-[a-z0-9-]+' "$README" | sort -u)
fi

summary="${#skills[@]} skill(s) checked - $errors error(s), $warnings warning(s)"

if [ "$errors" -gt 0 ]; then
    echo "$summary" >&2
    exit 1
fi

echo "OK    $summary"
exit 0
