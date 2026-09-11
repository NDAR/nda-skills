#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "format-java-modified must be run inside a Git worktree."
cd "$ROOT"

MAVEN_CMD="${MAVEN_CMD:-mvn}"
FORMATTER_PROFILE="${FORMATTER_PROFILE:-$SCRIPT_DIR/nda-ide-java-format.xml}"
FORMATTER_PLUGIN="${FORMATTER_PLUGIN:-net.revelc.code.formatter:formatter-maven-plugin:2.26.0}"
FORMATTER_INCLUDES="${FORMATTER_INCLUDES:-}"

[[ -f "$FORMATTER_PROFILE" ]] \
    || fail "Formatter profile not found: $FORMATTER_PROFILE"

collect_modified_java_files() {
    {
        git diff --name-only --diff-filter=ACMRTUXB -- '*.java'
        git diff --name-only --cached --diff-filter=ACMRTUXB -- '*.java'
        git ls-files --others --exclude-standard -- '*.java'
    } | sort -u
}

include_pattern_for_file() {
    local file="$1"
    case "$file" in
        src/main/java/*) printf '%s\n' "${file#src/main/java/}" ;;
        src/test/java/*) printf '%s\n' "${file#src/test/java/}" ;;
    esac
}

join_with_commas() {
    local IFS=,
    printf '%s\n' "$*"
}

if [[ -n "$FORMATTER_INCLUDES" ]]; then
    formatter_includes="$FORMATTER_INCLUDES"
else
    includes=()
    while IFS= read -r file; do
        pattern="$(include_pattern_for_file "$file")"
        [[ -n "$pattern" ]] && includes+=("$pattern")
    done < <(collect_modified_java_files)

    if [[ "${#includes[@]}" -eq 0 ]]; then
        echo "No modified Java files to format."
        exit 0
    fi

    unique_includes=()
    while IFS= read -r pattern; do
        unique_includes+=("$pattern")
    done < <(printf '%s\n' "${includes[@]}" | sort -u)

    formatter_includes="$(join_with_commas "${unique_includes[@]}")"
fi

echo "Running: $MAVEN_CMD $FORMATTER_PLUGIN:format -Dconfigfile=$FORMATTER_PROFILE -Dformatter.includes=$formatter_includes -Dlineending=LF -Dformatter.cache.skip=true"
"$MAVEN_CMD" "$FORMATTER_PLUGIN:format" \
    "-Dconfigfile=$FORMATTER_PROFILE" \
    "-Dformatter.includes=$formatter_includes" \
    "-Dlineending=LF" \
    "-Dformatter.cache.skip=true"
