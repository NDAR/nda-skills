#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "test-touched must be run inside a Git worktree."
cd "$ROOT"

MAVEN_CMD="${MAVEN_CMD:-mvn}"

print_only=false
if [[ "${1:-}" == "--print" ]]; then
    print_only=true
fi

collect_modified_java_files() {
    {
        git diff --name-only --diff-filter=ACMRTUXB -- '*.java'
        git diff --name-only --cached --diff-filter=ACMRTUXB -- '*.java'
        git ls-files --others --exclude-standard -- '*.java'
    } | sort -u
}

class_name_for_file() {
    basename "$1" .java
}

test_file_for_production_file() {
    local file="$1"
    local relative="${file#src/main/java/}"
    local test_file="src/test/java/${relative%.java}Test.java"

    [[ -f "$test_file" ]] && printf '%s\n' "$test_file"
    return 0
}

test_name_csv() {
    local IFS=,
    printf '%s\n' "$*"
}

tests=()

while IFS= read -r file; do
    case "$file" in
        src/test/java/*Test.java)
            tests+=("$(class_name_for_file "$file")")
            ;;
        src/main/java/*.java)
            test_file="$(test_file_for_production_file "$file")"
            if [[ -n "${test_file:-}" ]]; then
                tests+=("$(class_name_for_file "$test_file")")
            fi
            ;;
    esac
done < <(collect_modified_java_files)

if [[ "${#tests[@]}" -eq 0 ]]; then
    [[ "$print_only" == true ]] && exit 0
    echo "No direct touched tests found."
    exit 0
fi

unique_tests=()
while IFS= read -r test_name; do
    unique_tests+=("$test_name")
done < <(printf '%s\n' "${tests[@]}" | sort -u)
test_names="$(test_name_csv "${unique_tests[@]}")"

if [[ "$print_only" == true ]]; then
    printf '%s\n' "$test_names"
    exit 0
fi

echo "Running touched tests: $test_names"
"$MAVEN_CMD" "-Dtest=$test_names" test
