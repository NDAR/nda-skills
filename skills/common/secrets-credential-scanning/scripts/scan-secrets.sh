#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Secrets scan failed: %s\n' "$*" >&2
  exit 1
}

command -v gitleaks >/dev/null 2>&1 || fail 'gitleaks is not installed. Install it (e.g. "brew install gitleaks" or https://github.com/gitleaks/gitleaks/releases) and re-run.'
command -v python3 >/dev/null 2>&1 || fail 'python3 is required to parse the gitleaks report.'

mode=""
range=""

if [[ -n "${SECRETS_SCAN_BASE:-}" ]]; then
  mode="range"
  range="${SECRETS_SCAN_BASE}..${SECRETS_SCAN_HEAD:-HEAD}"
elif [[ "${SECRETS_SCAN_STAGED:-false}" == "true" ]]; then
  mode="staged"
else
  base=""
  for candidate in origin/HEAD origin/main origin/master; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
      if candidate_base=$(git merge-base HEAD "$candidate" 2>/dev/null); then
        base="$candidate_base"
        break
      fi
    fi
  done
  [[ -n "$base" ]] || fail 'Could not determine a base branch. Set SECRETS_SCAN_BASE explicitly (e.g. SECRETS_SCAN_BASE=origin/main) or SECRETS_SCAN_STAGED=true.'
  mode="range"
  range="${base}..${SECRETS_SCAN_HEAD:-HEAD}"
fi

report_dir=$(mktemp -d "${TMPDIR:-/tmp}/secrets-scan.XXXXXX")
trap 'rm -rf "$report_dir"' EXIT
report_path="$report_dir/report.json"

set +e
if [[ "$mode" == "range" ]]; then
  printf 'Running: gitleaks detect --log-opts=%s\n' "$range"
  gitleaks detect --source . --log-opts="$range" --report-format json --report-path "$report_path" --redact --no-banner
else
  printf 'Running: gitleaks protect --staged\n'
  gitleaks protect --source . --staged --report-format json --report-path "$report_path" --redact --no-banner
fi
gitleaks_status=$?
set -e

(( gitleaks_status == 0 || gitleaks_status == 1 )) || fail "gitleaks exited with unexpected status $gitleaks_status."

[[ -f "$report_path" ]] || fail "gitleaks exited with status $gitleaks_status but produced no report file at $report_path — treat this as a scan failure, not a clean pass."

python3 - "$report_path" "$gitleaks_status" <<'PY'
import json
import sys

path = sys.argv[1]
gitleaks_status = int(sys.argv[2])
try:
    with open(path) as handle:
        content = handle.read().strip()
except FileNotFoundError:
    content = ""

findings = json.loads(content) if content else []

if not findings and gitleaks_status == 1:
    print(
        "Secrets scan failed: gitleaks exited with status 1 (findings-or-error) "
        "but the report contains no findings — treating this as a tool error, "
        "not a clean pass.",
        file=sys.stderr,
    )
    raise SystemExit(1)

def mask(secret):
    if not secret:
        return "<redacted>"
    if len(secret) <= 4:
        return "*" * len(secret)
    return secret[:2] + "*" * (len(secret) - 4) + secret[-2:]

if not findings:
    print("No secrets detected.")
    raise SystemExit(0)

print(f"Secrets scan found {len(findings)} finding(s):")
for item in findings:
    file_path = item.get("File", "<unknown file>")
    line = item.get("StartLine", "?")
    rule = item.get("RuleID", "<unknown rule>")
    commit = item.get("Commit") or "<uncommitted>"
    secret = mask(item.get("Secret", ""))
    print(f"  {file_path}:{line} rule={rule} commit={commit} secret={secret}")
raise SystemExit(1)
PY

printf 'Secrets scan passed: no findings (%s).\n' "${range:-staged changes}"
