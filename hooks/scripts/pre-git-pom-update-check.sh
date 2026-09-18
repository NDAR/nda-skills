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

def commit_invocation(segment):
    for position, token in enumerate(segment):
        if os.path.basename(token) != "git":
            continue
        override = False
        index = position + 1
        while index < len(segment) and segment[index].startswith("-"):
            option = segment[index]
            index += 1
            if option in {"-C", "--git-dir", "--work-tree"} or option.startswith(
                ("--git-dir=", "--work-tree=")
            ):
                return "unsafe", "Maven version check requires a plain Git commit without repository-relocating options. Reissue the plain Git commit from the intended repository."
            if option in options_with_values and "=" not in option:
                if index >= len(segment):
                    return "unsafe", "Maven version check could not parse the requested Git command. Reissue the plain Git commit from the intended repository."
                value = segment[index]
                if option == "-c":
                    name, separator, override_reason = value.partition("=")
                    if name == "nda.pom-update-check.override":
                        if (
                            separator != "="
                            or not override_reason.strip()
                            or any(character in override_reason for character in "$`\\")
                        ):
                            return "unsafe", "Maven version check requires a literal, non-empty override reason. Reissue the plain Git commit from the intended repository."
                        override = True
                index += 1
        if index < len(segment) and segment[index] == "commit":
            if position != 0:
                return "unsafe", "Maven version check requires a plain Git commit without command wrappers. Reissue the plain Git commit from the intended repository."
            return "commit", override
    return "none", False

if len(segments) != 1:
    for segment in segments:
        kind, _detail = commit_invocation(segment)
        if kind != "none":
            sys.stdout.buffer.write(
                cwd.encode()
                + b"\0false\0Maven version check requires a plain Git commit without shell composition. Reissue the plain Git commit from the intended repository.\0"
            )
            raise SystemExit(0)
    raise SystemExit(0)

kind, detail = commit_invocation(segments[0])
if kind == "none":
    raise SystemExit(0)
if kind == "unsafe":
    sys.stdout.buffer.write(cwd.encode() + b"\0false\0" + detail.encode() + b"\0")
    raise SystemExit(0)

sys.stdout.buffer.write(cwd.encode() + b"\0" + str(detail).lower().encode() + b"\0\0")
')

if (( ${#fields[@]} == 0 )); then
  exit 0
fi

if (( ${#fields[@]} != 3 )); then
  deny 'Maven version check could not parse the requested Git commit command.'
fi

cwd=${fields[0]}
override=${fields[1]}
unsafe_reason=${fields[2]}

if [[ -n "$unsafe_reason" ]]; then
  deny "$unsafe_reason"
fi

git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) ||
  deny 'Maven version check could not locate a Git repository before Git commit.'

[[ -f "$git_root/pom.xml" ]] || exit 0

if [[ "$override" == "true" ]]; then
  exit 0
fi

if [[ -z "${PLUGIN_ROOT:-}" ]]; then
  deny 'Maven version check is unavailable before Git commit: PLUGIN_ROOT is not set.'
fi

checker="$PLUGIN_ROOT/hooks/scripts/check-pom-updates.py"
if [[ ! -f "$checker" ]]; then
  deny 'Maven version check is unavailable before Git commit: checker script is missing.'
fi

report=$(mktemp "${TMPDIR:-/tmp}/pre-git-pom-update-check.XXXXXX")
trap 'rm -f "$report"' EXIT

set +e
python3 "$checker" --project "$git_root" --fail-on-outdated >"$report" 2>&1
check_status=$?
set -e

if (( check_status == 0 )); then
  exit 0
fi

check_output=$(<"$report")
if (( check_status == 1 )); then
  deny "Maven version updates are available. Ask the user whether to update the POM or explicitly override this check before retrying Git commit. After explicit user approval, retry with git -c nda.pom-update-check.override=<reason> commit ..."$'\n\n'"$check_output"
fi

deny "Maven version check failed before Git commit. Resolve the check error, then retry."$'\n\n'"$check_output"
