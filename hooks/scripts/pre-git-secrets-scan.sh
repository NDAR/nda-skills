#!/usr/bin/env bash
set -euo pipefail

deny() {
  python3 - "$1" <<'PY'
import json
import sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1],
    }
}))
PY
  exit 2
}

fields=()
while IFS= read -r -d '' field; do
  fields+=("$field")
done < <(python3 -c '
import json
import os
import re
import shlex
import sys

try:
    payload = json.load(sys.stdin)
    cwd = payload["cwd"]
    tool_input = payload["tool_input"]
    if not isinstance(tool_input, dict):
        raise TypeError
    command = tool_input.get("command")
    if command is None:
        command = tool_input.get("cmd")
except (KeyError, TypeError, json.JSONDecodeError):
    raise SystemExit(0)

if not isinstance(cwd, str) or not isinstance(command, str):
    raise SystemExit(0)

try:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
    lexer.whitespace_split = True
    tokens = list(lexer)
except ValueError:
    raise SystemExit(0)

segments = [[]]
for token in tokens:
    if token and all(character in ";&|" for character in token):
        segments.append([])
    else:
        segments[-1].append(token)

options_with_values = {
    "-C", "-c", "--config-env", "--exec-path", "--git-dir", "--namespace",
    "--super-prefix", "--work-tree",
}
action = None
for segment in segments:
    if not segment or os.path.basename(segment[0]) != "git":
        continue
    index = 1
    while index < len(segment) and segment[index].startswith("-"):
        option = segment[index]
        index += 1
        if option in options_with_values and "=" not in option:
            index += 1
    if index < len(segment) and segment[index] in {"commit", "push"}:
        action = segment[index]
        break

if action is not None:
    sys.stdout.buffer.write(cwd.encode() + b"\0" + action.encode() + b"\0")
')

if (( ${#fields[@]} == 0 )); then
  exit 0
fi

if (( ${#fields[@]} != 2 )); then
  deny 'Secret scan hook could not parse the requested Git command.'
fi

cwd=${fields[0]}
action=${fields[1]}

if [[ -z "${PLUGIN_ROOT:-}" ]]; then
  deny "Secret scan hook is unavailable before Git $action: PLUGIN_ROOT is not set."
fi

scanner="$PLUGIN_ROOT/skills/common/secrets-credential-scanning/scripts/scan-secrets.sh"
if [[ ! -x "$scanner" ]]; then
  deny "Secret scan hook is unavailable before Git $action: scanner script is missing."
fi

git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) ||
  deny "Secret scan hook could not locate a Git repository before Git $action."

scan_output=$(mktemp "${TMPDIR:-/tmp}/pre-git-secrets-scan.XXXXXX")
trap 'rm -f "$scan_output"' EXIT

set +e
if [[ "$action" == "commit" ]]; then
  (
    cd "$git_root"
    SECRETS_SCAN_STAGED=true "$scanner"
  ) >"$scan_output" 2>&1
else
  (
    cd "$git_root"
    "$scanner"
  ) >"$scan_output" 2>&1
fi
scan_status=$?
set -e

if (( scan_status != 0 )); then
  deny "Secret scan failed before Git $action. Resolve the redacted scan findings or scanner error, then retry."
fi
