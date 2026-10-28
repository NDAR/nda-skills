#!/usr/bin/env bash
set -euo pipefail

# Commands are trusted, repository-selected shell code, never user input.
for name in FORMAT_CHECK_CMD ANGULAR_LINT_CMD TEST_TOUCHED_CMD; do
  if [[ -z ${!name:-} ]]; then
    printf 'Fast checks failed: set %s to a repository-supported command.\n' "$name" >&2
    exit 1
  fi
done

for name in FORMAT_CHECK_CMD ANGULAR_LINT_CMD TEST_TOUCHED_CMD; do
  printf 'Running %s\n' "$name"
  bash -e -o pipefail -c "${!name}"
done
git diff --check
git diff --cached --check
printf 'Fast checks passed; final Angular verification is still required.\n'
