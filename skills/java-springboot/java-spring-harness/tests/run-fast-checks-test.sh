#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runner="$skill_dir/scripts/run-fast-checks.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/java-spring-harness.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

make_repo() {
  local name=$1
  local directory="$fixture/$name"

  mkdir -p "$directory"
  git -C "$directory" init -q
  git -C "$directory" config user.email test@example.com
  git -C "$directory" config user.name test
  printf '%s\n' "$directory"
}

make_logging_script() {
  local path=$1
  local log=$2
  local label=$3
  local exit_code=${4:-0}

  printf '%s\n' '#!/usr/bin/env bash' \
    "if [ \"\$#\" -gt 0 ]; then printf '%s %s\\n' '$label' \"\$*\" >> '$log'; else printf '%s\\n' '$label' >> '$log'; fi" \
    "exit $exit_code" \
    > "$path"
  chmod +x "$path"
}

make_test_touched_print_script() {
  local path=$1
  local log=$2
  local touched_tests=$3

  printf '%s\n' '#!/usr/bin/env bash' \
    "printf 'test-touched %s\\n' \"\$*\" >> '$log'" \
    "printf '%s\\n' '$touched_tests'" \
    > "$path"
  chmod +x "$path"
}

passing_repo=$(make_repo passing)
log="$passing_repo/steps.log"
make_logging_script "$passing_repo/format.sh" "$log" format
make_test_touched_print_script "$passing_repo/test-touched.sh" "$log" FooTest
make_logging_script "$passing_repo/mvn.sh" "$log" mvn
make_logging_script "$passing_repo/diff-check.sh" "$log" diff-check

output=$(
  cd "$passing_repo"
  FORMAT_JAVA_MODIFIED_CMD="$passing_repo/format.sh" \
  TEST_TOUCHED_CMD="$passing_repo/test-touched.sh" \
  MAVEN_CMD="$passing_repo/mvn.sh" \
  GIT_DIFF_CHECK_CMD="$passing_repo/diff-check.sh" \
  "$runner"
)
test "$(<"$log")" = "$(printf '%s\n%s\n%s\n%s' \
  'format' 'test-touched --print' 'mvn -Dtest=LayeredArchitectureTest,FooTest test' 'diff-check')"
grep -Fq 'Fast harness checks passed.' <<<"$output"
grep -Fq 'mvn -B -s settings.xml clean verify' <<<"$output"

no_touched_repo=$(make_repo no-touched)
log="$no_touched_repo/steps.log"
make_logging_script "$no_touched_repo/format.sh" "$log" format
make_test_touched_print_script "$no_touched_repo/test-touched.sh" "$log" ""
make_logging_script "$no_touched_repo/mvn.sh" "$log" mvn
make_logging_script "$no_touched_repo/diff-check.sh" "$log" diff-check

(
  cd "$no_touched_repo"
  FORMAT_JAVA_MODIFIED_CMD="$no_touched_repo/format.sh" \
  TEST_TOUCHED_CMD="$no_touched_repo/test-touched.sh" \
  MAVEN_CMD="$no_touched_repo/mvn.sh" \
  GIT_DIFF_CHECK_CMD="$no_touched_repo/diff-check.sh" \
  "$runner" >/dev/null
)
test "$(<"$log")" = "$(printf '%s\n%s\n%s\n%s' \
  'format' 'test-touched --print' 'mvn -Dtest=LayeredArchitectureTest test' 'diff-check')"

failing_repo=$(make_repo failing)
log="$failing_repo/steps.log"
make_logging_script "$failing_repo/format.sh" "$log" format 1
make_logging_script "$failing_repo/test-touched.sh" "$log" test-touched
make_logging_script "$failing_repo/mvn.sh" "$log" mvn

if (
  cd "$failing_repo"
  FORMAT_JAVA_MODIFIED_CMD="$failing_repo/format.sh" \
  TEST_TOUCHED_CMD="$failing_repo/test-touched.sh" \
  MAVEN_CMD="$failing_repo/mvn.sh" \
  "$runner"
); then
  printf 'Expected a failing format step to stop the run.\n' >&2
  exit 1
fi
if [[ -f "$log" ]] && grep -Fq 'mvn' "$log"; then
  printf 'Expected the run to stop before invoking Maven after a failed step.\n' >&2
  exit 1
fi

non_repo="$fixture/not-a-repo"
mkdir -p "$non_repo"
if error=$(cd "$non_repo" && "$runner" 2>&1); then
  printf 'Expected the runner to fail outside a git repository.\n' >&2
  exit 1
fi
grep -Fq 'Not inside a git repository.' <<<"$error"

printf 'PASS: fast harness steps run in order, stop on failure, and require a git repository.\n'
