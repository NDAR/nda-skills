#!/usr/bin/env bash
set -euo pipefail

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
wrapper="$hook_dir/scripts/pre-git-secrets-scan.sh"
repo_root=$(cd "$hook_dir/.." && pwd)

fixture=$(mktemp -d "${TMPDIR:-/tmp}/pre-git-secrets-scan-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

repo="$fixture/repo"
mkdir -p "$repo/nested"
git -C "$repo" init -q

plugin_root="$fixture/plugin"
scanner="$plugin_root/skills/common/secrets-credential-scanning/scripts/scan-secrets.sh"
mkdir -p "$(dirname "$scanner")"
cat > "$scanner" <<'SCANNER'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "${SECRETS_SCAN_STAGED:-range}" >> "$FAKE_SCAN_LOG"
printf '%s\n' 'scanner-output-must-not-be-forwarded'
exit "${FAKE_SCAN_EXIT:-0}"
SCANNER
chmod +x "$scanner"

run_hook() {
  local command=$1
  printf '{"cwd":"%s","tool_input":{"command":"%s"}}\n' "$repo/nested" "$command" |
    PLUGIN_ROOT="$plugin_root" \
    FAKE_SCAN_LOG="$fixture/scans.log" \
    "$wrapper"
}

# A commit scans staged changes and permits a clean result.
if ! clean_output=$(FAKE_SCAN_EXIT=0 run_hook 'git commit -m message'); then
  printf 'Expected a clean Git commit scan to pass.\n' >&2
  exit 1
fi
[[ -z "$clean_output" ]]
grep -Fxq 'true' "$fixture/scans.log"

# A finding blocks the Git command and never forwards scanner output.
set +e
finding_output=$(FAKE_SCAN_EXIT=1 run_hook 'git commit -m message')
finding_status=$?
set -e
if (( finding_status != 2 )); then
  printf 'Expected a secret finding to deny Git commit with status 2, got %s.\n' "$finding_status" >&2
  exit 1
fi
if grep -Fq 'scanner-output-must-not-be-forwarded' <<<"$finding_output"; then
  printf 'Expected scanner output to remain hidden on a finding.\n' >&2
  exit 1
fi
python3 -c '
import json
import sys

payload = json.load(sys.stdin)
output = payload["hookSpecificOutput"]
assert output["hookEventName"] == "PreToolUse"
assert output["permissionDecision"] == "deny"
assert "Git commit" in output["permissionDecisionReason"]
' <<<"$finding_output"

# Tool errors also deny the Git command.
set +e
error_output=$(FAKE_SCAN_EXIT=70 run_hook 'git commit -m message')
error_status=$?
set -e
if (( error_status != 2 )); then
  printf 'Expected a scanner error to deny Git commit with status 2, got %s.\n' "$error_status" >&2
  exit 1
fi
grep -Fq 'Git commit' <<<"$error_output"

# A push scans the branch range rather than staged changes.
if ! push_output=$(FAKE_SCAN_EXIT=0 run_hook 'git push origin topic'); then
  printf 'Expected a clean Git push scan to pass.\n' >&2
  exit 1
fi
[[ -z "$push_output" ]]
grep -Fxq 'range' "$fixture/scans.log"

# Other shell commands do not invoke the scanner.
scan_count_before=$(wc -l < "$fixture/scans.log")
if ! no_op_output=$(FAKE_SCAN_EXIT=70 run_hook 'echo not-a-git-command'); then
  printf 'Expected a non-Git command to be ignored.\n' >&2
  exit 1
fi
[[ -z "$no_op_output" ]]
scan_count_after=$(wc -l < "$fixture/scans.log")
if [[ "$scan_count_before" != "$scan_count_after" ]]; then
  printf 'Expected a non-Git command not to invoke the scanner.\n' >&2
  exit 1
fi

# The plugin exposes the wrapper as a synchronous PreToolUse Bash hook.
python3 - "$repo_root/.codex-plugin/plugin.json" "$repo_root/hooks/hooks.json" <<'PY'
import json
import sys

manifest_path, hooks_path = sys.argv[1:]
with open(manifest_path) as handle:
    manifest = json.load(handle)
with open(hooks_path) as handle:
    config = json.load(handle)

assert manifest["hooks"] == "./hooks/hooks.json"
handler = config["hooks"]["PreToolUse"][0]["hooks"][0]
assert config["hooks"]["PreToolUse"][0]["matcher"] == "Bash"
assert handler["type"] == "command"
assert "${PLUGIN_ROOT}/hooks/scripts/pre-git-secrets-scan.sh" in handler["command"]
assert handler["timeout"] == 120
assert handler.get("async") is not True
PY

printf 'PASS: pre-Git secret scanning hook gates commit/push and ignores unrelated commands.\n'
