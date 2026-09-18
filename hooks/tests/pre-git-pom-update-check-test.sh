#!/usr/bin/env bash
set -euo pipefail

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wrapper="$hook_dir/scripts/pre-git-pom-update-check.sh"

fixture=$(mktemp -d "${TMPDIR:-/tmp}/pre-git-pom-update-check-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

repo="$fixture/repo"
mkdir -p "$repo/nested"
git -C "$repo" init -q
printf '<project/>\n' > "$repo/pom.xml"

plugin_root="$fixture/plugin"
checker="$plugin_root/hooks/scripts/check-pom-updates.py"
mkdir -p "$(dirname "$checker")"
cat > "$checker" <<'CHECKER'
#!/usr/bin/env python3
import os
import sys

if os.environ.get('FAKE_CHECK_EXIT') == '2':
    print('simulated Maven metadata failure', file=sys.stderr)
    raise SystemExit(2)

print('# Maven Version Update Report')
print('## Outdated dependencies')
print('| com.example:library | 1.0.0 | 1.1.0 |')
raise SystemExit(1)
CHECKER
chmod +x "$checker"

set +e
output=$(printf '{"cwd":"%s","tool_input":{"cmd":"git commit -m message"}}\n' "$repo/nested" |
  PLUGIN_ROOT="$plugin_root" "$wrapper")
status=$?
set -e

if (( status != 2 )); then
  printf 'Expected an outdated version check to deny Git commit with status 2, got %s.\n%s\n' "$status" "$output" >&2
  exit 1
fi
python3 -c '
import json
import sys

payload = json.load(sys.stdin)
hook_output = payload["hookSpecificOutput"]
assert hook_output["hookEventName"] == "PreToolUse"
assert hook_output["permissionDecision"] == "deny"
reason = hook_output["permissionDecisionReason"]
assert "Maven version updates are available" in reason
assert "com.example:library" in reason
assert "\n\n# Maven Version Update Report" in reason
' <<<"$output"

printf 'PASS: outdated Maven versions deny a Git commit with the update report.\n'

# An explicit Git configuration override permits a commit after the user has
# chosen to defer the available version updates.
if ! override_output=$(printf '{"cwd":"%s","tool_input":{"command":"git -c nda.pom-update-check.override=defer-update commit -m message"}}\n' "$repo/nested" |
  PLUGIN_ROOT="$plugin_root" "$wrapper"); then
  printf 'Expected an explicit Maven version override to permit Git commit.\n%s\n' "$override_output" >&2
  exit 1
fi
[[ -z "$override_output" ]]

printf 'PASS: an explicit Maven version override permits a Git commit.\n'

# The hook sees Bash source before expansion. A variable-looking reason may
# expand to empty at execution time, so it must not authorize an override.
expanded_override_command='git -c nda.pom-update-check.override=$EMPTY_OVERRIDE commit -m message'
set +e
expanded_override_output=$(printf '{"cwd":"%s","tool_input":{"command":"%s"}}\n' "$repo/nested" "$expanded_override_command" |
  EMPTY_OVERRIDE='' PLUGIN_ROOT="$plugin_root" "$wrapper")
expanded_override_status=$?
set -e
if (( expanded_override_status != 2 )); then
  printf 'Expected a shell-expanded override to be denied, got %s.\n%s\n' "$expanded_override_status" "$expanded_override_output" >&2
  exit 1
fi
python3 -c '
import json
import sys

reason = json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"]
assert "literal" in reason
' <<<"$expanded_override_output"

printf 'PASS: shell-expanded Maven version overrides are denied.\n'

# A checker error is not evidence that the POM is current, so it blocks the
# commit with the diagnostic output needed to resolve it.
set +e
error_output=$(printf '{"cwd":"%s","tool_input":{"command":"git commit -m message"}}\n' "$repo/nested" |
  PLUGIN_ROOT="$plugin_root" FAKE_CHECK_EXIT=2 "$wrapper")
error_status=$?
set -e
if (( error_status != 2 )); then
  printf 'Expected a failed Maven version check to deny Git commit with status 2, got %s.\n%s\n' "$error_status" "$error_output" >&2
  exit 1
fi
python3 -c '
import json
import sys

reason = json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"]
assert "Maven version check failed" in reason
assert "simulated Maven metadata failure" in reason
' <<<"$error_output"

printf 'PASS: failed Maven checks deny a Git commit with diagnostics.\n'

# Shell composition and repository relocation make the actual commit target
# ambiguous to this hook. They must be denied instead of silently skipping the
# POM check.
outside_repo="$fixture/outside-repo"
mkdir -p "$outside_repo/nested"
git -C "$outside_repo" init -q

for command in \
  'cd /tmp && git commit -m message' \
  'git status && git commit -m message' \
  'env GIT_OPTIONAL_LOCKS=0 git commit -m message' \
  "git -C $repo commit -m message"; do
  set +e
  unsafe_output=$(printf '{"cwd":"%s","tool_input":{"command":"%s"}}\n' "$outside_repo/nested" "$command" |
    PLUGIN_ROOT="$plugin_root" "$wrapper")
  unsafe_status=$?
  set -e
  if (( unsafe_status != 2 )); then
    printf 'Expected unsupported Git commit form to be denied, got %s for %s.\n%s\n' "$unsafe_status" "$command" "$unsafe_output" >&2
    exit 1
  fi
  python3 -c '
import json
import sys

reason = json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"]
assert "plain Git commit" in reason
' <<<"$unsafe_output"
done

printf 'PASS: ambiguous Git commit forms are denied instead of skipping the POM check.\n'

# The plugin must expose each gate once through a compatibility matcher, so a
# tool that reports both Bash and exec aliases cannot run either gate twice.
python3 - "$hook_dir/../.codex-plugin/plugin.json" "$hook_dir/hooks.json" <<'PY'
import json
import sys

manifest_path, hooks_path = sys.argv[1:]
with open(manifest_path) as handle:
    manifest = json.load(handle)
with open(hooks_path) as handle:
    config = json.load(handle)

assert manifest["hooks"] == "./hooks/hooks.json"
registrations = config["hooks"]["PreToolUse"]
assert len(registrations) == 1
registration = registrations[0]
assert registration["matcher"] == "^(?:Bash|exec|exec_command)$"
handlers = registration["hooks"]
assert {handler["command"] for handler in handlers} == {
    '"${PLUGIN_ROOT}/hooks/scripts/pre-git-secrets-scan.sh"',
    '"${PLUGIN_ROOT}/hooks/scripts/pre-git-pom-update-check.sh"',
}
assert {handler["timeout"] for handler in handlers} == {120, 300}
assert all(handler["type"] == "command" for handler in handlers)
assert all(handler.get("async") is not True for handler in handlers)
PY

printf 'PASS: pre-Git Maven version check is registered as a synchronous plugin hook.\n'
