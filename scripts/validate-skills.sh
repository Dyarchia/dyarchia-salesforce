#!/usr/bin/env bash
set -uo pipefail

SOURCE_ROOT="${SOURCE_ROOT:-skills}"
OUTPUT_ROOT="${OUTPUT_ROOT:-dist}"
SKILL_MD_WARN_BYTES="${SKILL_MD_WARN_BYTES:-20480}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/$SOURCE_ROOT"
OUTPUT_DIR="$REPO_ROOT/$OUTPUT_ROOT"
README="$REPO_ROOT/README.md"
SHARED_DIR="$REPO_ROOT/references-shared"
PLUGIN_MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"

INVOCATION_CLAUSE='Load only when the user explicitly invokes this skill by name'
# README names that are deliberately dya-prefixed without a folder under skills/.
NON_SKILL_TOKENS=" "

# Skills whose domain has no Salesforce core API version: B2C Commerce is Demandware
# lineage, the CLI versions on its own cadence. They are exempt from the platform check.
VERSION_NEUTRAL_SKILLS=" dya-b2c-commerce dya-sf-cli "

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

# README is the single source of truth for the platform version. Everything else - every
# Platform Context heading, the badge, the plugin description - is checked against it, so a
# version bump cannot land half-applied.
PLATFORM_VERSION=""
if [ -s "$README" ]; then
    PLATFORM_VERSION="$(sed -n 's/^[0-9]* skills, all targeting \*\*\(.*\)\*\*.*$/\1/p' "$README" | head -1)"
fi
if [ -z "$PLATFORM_VERSION" ]; then
    fail "README.md has no 'N skills, all targeting **<version>**' line to read the platform version from"
else
    BADGE_VERSION="$(sed -n 's/.*Salesforce%20API-\(v[0-9.]*\)-.*/\1/p' "$README" | head -1)"
    if [ -z "$BADGE_VERSION" ]; then
        fail "README.md has no Salesforce API version badge"
    elif ! printf '%s' "$PLATFORM_VERSION" | grep -qF "$BADGE_VERSION"; then
        fail "README.md badge says '$BADGE_VERSION' but the catalogue line says '$PLATFORM_VERSION'"
    fi
fi

read_shared_manifest() {
    [ -f "$1" ] || return 0
    sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" |
        grep -v '^#' | grep -v '^$' |
        sed -e 's/\.md$//' -e 's/$/.md/' |
        LC_ALL=C sort -u
}

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

    if [ -n "$PLATFORM_VERSION" ]; then
        case "$VERSION_NEUTRAL_SKILLS" in
            *" $name "*) : ;;
            *)
                if ! grep -qF "## Platform Context — $PLATFORM_VERSION" "$skill_md"; then
                    fail "$name : Platform Context does not declare '$PLATFORM_VERSION'"
                fi
                ;;
        esac
    fi

    refs_dir="$src/references"
    if [ -d "$refs_dir" ]; then
        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            if ! grep -qF "$ref" "$skill_md"; then
                fail "$name : references/$ref is never cited from SKILL.md"
            fi
        done < <(find "$refs_dir" -type f -printf '%f
')
    elif [ "$md_bytes" -gt "$SKILL_MD_WARN_BYTES" ]; then
        warn "$name : SKILL.md is over the ceiling and has no references/ to move detail into"
    fi

    declared="$(read_shared_manifest "$src/shared-refs.txt")"
    shared_target="$refs_dir/shared"
    if [ -n "$declared" ]; then
        while IFS= read -r fragment; do
            [ -n "$fragment" ] || continue
            if [ ! -f "$SHARED_DIR/$fragment" ]; then
                fail "$name : shared-refs.txt declares '$fragment', which is not in references-shared/"
            elif [ ! -f "$shared_target/$fragment" ]; then
                fail "$name : shared fragment '$fragment' is declared but not synced - run scripts/sync-shared-refs"
            elif [ "$(sha256sum "$shared_target/$fragment" | cut -d' ' -f1)" !=                    "$(sha256sum "$SHARED_DIR/$fragment" | cut -d' ' -f1)" ]; then
                fail "$name : shared fragment '$fragment' differs from its canon - never edit a copy, edit references-shared/ and re-sync"
            fi
        done <<< "$declared"
    fi
    if [ -d "$shared_target" ]; then
        while IFS= read -r stray; do
            [ -n "$stray" ] || continue
            if ! grep -qxF "$stray" <<< "$declared"; then
                fail "$name : references/shared/$stray is not declared in shared-refs.txt - run scripts/sync-shared-refs"
            fi
        done < <(find "$shared_target" -maxdepth 1 -type f -printf '%f
')
    fi

    if [ -s "$README" ] && ! grep -qE "^- \*\*\`$name\`\*\*[[:space:]]*$" "$README"; then
        fail "$name : not listed in the README.md catalogue"
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

PLUGIN_VERSION=""
if [ -f "$PLUGIN_MANIFEST" ]; then
    PLUGIN_VERSION="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_MANIFEST" | head -1)"
    if [ -n "$PLATFORM_VERSION" ] && ! grep -qF "$PLATFORM_VERSION" "$PLUGIN_MANIFEST"; then
        fail ".claude-plugin/plugin.json description does not state '$PLATFORM_VERSION'"
    fi
else
    fail ".claude-plugin/plugin.json not found"
fi

if [ -f "$MARKETPLACE_MANIFEST" ]; then
    MARKETPLACE_VERSION="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MARKETPLACE_MANIFEST" | head -1)"
    if ! grep -qF '"dyarchia-salesforce"' "$MARKETPLACE_MANIFEST"; then
        fail ".claude-plugin/marketplace.json has no 'dyarchia-salesforce' plugin entry"
    elif [ -n "$PLUGIN_VERSION" ] && [ "$MARKETPLACE_VERSION" != "$PLUGIN_VERSION" ]; then
        fail "plugin.json version '$PLUGIN_VERSION' and marketplace.json version '$MARKETPLACE_VERSION' disagree"
    fi
else
    fail ".claude-plugin/marketplace.json not found"
fi

if [ -s "$README" ]; then
    while read -r token; do
        [ -z "$token" ] && continue
        case " ${skills[*]} " in *" $token "*) continue ;; esac
        case "$NON_SKILL_TOKENS" in *" $token "*) continue ;; esac
        warn "README.md references '$token', which is not a skill folder"
    done < <(grep -oE 'dya-[a-z0-9-]+' "$README" | sort -u)
fi

summary="${#skills[@]} skill(s) checked - $errors error(s), $warnings warning(s)"

if [ "$errors" -gt 0 ]; then
    echo "$summary" >&2
    exit 1
fi

echo "OK    $summary"
exit 0
