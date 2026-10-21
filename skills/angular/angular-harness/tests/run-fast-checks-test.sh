#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runner="$skill_dir/scripts/run-fast-checks.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
git init -q

if bash "$runner" >output 2>&1; then
  echo 'FAIL: missing commands must fail' >&2; exit 1
fi
FORMAT_CHECK_CMD='echo format >> calls' \
ANGULAR_LINT_CMD='echo lint >> calls' \
TEST_TOUCHED_CMD='echo test >> calls' bash "$runner"
test "$(cat calls)" = $'format\nlint\ntest'

if FORMAT_CHECK_CMD='exit 7' ANGULAR_LINT_CMD='touch should-not-run' \
  TEST_TOUCHED_CMD='true' bash "$runner"; then
  echo 'FAIL: formatting failure must propagate' >&2; exit 1
fi
test ! -f should-not-run

printf 'clean\n' > tracked
git add tracked
printf 'bad whitespace  \n' > tracked
if FORMAT_CHECK_CMD=true ANGULAR_LINT_CMD=true TEST_TOUCHED_CMD=true bash "$runner"; then
  echo 'FAIL: whitespace errors must fail' >&2; exit 1
fi
echo 'PASS: fast checks require explicit commands, preserve order, and propagate failures.'
