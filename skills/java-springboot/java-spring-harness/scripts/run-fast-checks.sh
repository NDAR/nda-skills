#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Fast harness checks failed: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail 'Not inside a git repository.'
cd "$ROOT"

FORMAT_JAVA_MODIFIED_CMD="${FORMAT_JAVA_MODIFIED_CMD:-$SCRIPT_DIR/format-java-modified.sh}"
TEST_TOUCHED_CMD="${TEST_TOUCHED_CMD:-$SCRIPT_DIR/test-touched.sh}"
MAVEN_CMD="${MAVEN_CMD:-mvn}"
ARCHITECTURE_TEST_CLASS="${ARCHITECTURE_TEST_CLASS:-LayeredArchitectureTest}"
GIT_DIFF_CHECK_CMD="${GIT_DIFF_CHECK_CMD:-}"

run_step() {
  local label="$1"
  shift

  echo "==> $label"
  "$@"
}

run_git_diff_check() {
  if [[ -n "$GIT_DIFF_CHECK_CMD" ]]; then
    "$GIT_DIFF_CHECK_CMD"
  else
    git diff --check
  fi
}

run_architecture_and_touched_tests() {
  local touched_tests test_list
  touched_tests="$("$TEST_TOUCHED_CMD" --print)"

  test_list="$ARCHITECTURE_TEST_CLASS"
  [[ -n "$touched_tests" ]] && test_list="$test_list,$touched_tests"

  echo "Running: $MAVEN_CMD -Dtest=$test_list test"
  "$MAVEN_CMD" "-Dtest=$test_list" test
}

run_step "Format modified Java files" "$FORMAT_JAVA_MODIFIED_CMD"
run_step "Run architecture sensor and touched tests" run_architecture_and_touched_tests
run_step "Check diff whitespace" run_git_diff_check

echo "Fast harness checks passed."
echo "For full verification, run: mvn -B -s settings.xml clean verify"
