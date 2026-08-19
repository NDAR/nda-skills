#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scanner="$skill_dir/scripts/scan-secrets.sh"

fixture=$(mktemp -d "${TMPDIR:-/tmp}/secrets-scan-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

bin_dir="$fixture/bin"
mkdir -p "$bin_dir"
cat > "$bin_dir/gitleaks" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> gitleaks.args
report_path=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--report-path" ]]; then
    report_path="$arg"
  fi
  prev="$arg"
done
if [[ -n "$report_path" ]]; then
  printf '%s' "${FAKE_GITLEAKS_REPORT:-[]}" > "$report_path"
fi
exit "${FAKE_GITLEAKS_EXIT:-0}"
SHIM
chmod +x "$bin_dir/gitleaks"

make_repo() {
  local name=$1
  local directory="$fixture/$name"
  mkdir -p "$directory"
  (
    cd "$directory"
    git init -q
    git config user.email test@example.com
    git config user.name test
    printf 'placeholder\n' > file.txt
    git add file.txt
    git commit -qm 'initial'
  )
  printf '%s\n' "$directory"
}

# 1. Clean range passes and reports no findings.
clean_repo=$(make_repo clean)
if ! clean_output=$(
  cd "$clean_repo"
  PATH="$bin_dir:$PATH" \
  SECRETS_SCAN_BASE=HEAD \
  FAKE_GITLEAKS_REPORT='[]' \
  FAKE_GITLEAKS_EXIT=0 \
  "$scanner"
); then
  printf 'Expected a clean range to pass.\n' >&2
  exit 1
fi
grep -Fq 'No secrets detected.' <<<"$clean_output"
grep -Fq 'Secrets scan passed' <<<"$clean_output"
# gitleaks auto-loads a repo-root .gitleaks.toml only when given --source .;
# this is the only way an allowlist actually takes effect, so assert we pass it.
grep -Fq -- '--source .' "$clean_repo/gitleaks.args"
# --redact is the only thing preventing gitleaks' own console output from containing a raw secret.
grep -Fq -- '--redact' "$clean_repo/gitleaks.args"

# 2. A finding fails the scan and redacts the raw secret value.
leak_repo=$(make_repo leak)
leak_secret='AKIAIOSFODNN7EXAMPLE'
leak_report=$(printf '[{"File":"config.py","StartLine":3,"RuleID":"aws-access-key","Commit":"abc123","Secret":"%s"}]' "$leak_secret")
set +e
leak_output=$(
  cd "$leak_repo"
  PATH="$bin_dir:$PATH" \
  SECRETS_SCAN_BASE=HEAD \
  FAKE_GITLEAKS_REPORT="$leak_report" \
  FAKE_GITLEAKS_EXIT=1 \
  "$scanner"
)
leak_status=$?
set -e
if (( leak_status == 0 )); then
  printf 'Expected a gitleaks finding to fail the scan.\n' >&2
  exit 1
fi
grep -Fq 'config.py:3' <<<"$leak_output"
grep -Fq 'rule=aws-access-key' <<<"$leak_output"
if grep -Fq "$leak_secret" <<<"$leak_output"; then
  printf 'Expected the raw secret value to be redacted from output.\n' >&2
  exit 1
fi
expected_masked=$(python3 -c "s='$leak_secret'; print(s[:2] + '*' * (len(s) - 4) + s[-2:])")
grep -Fq "$expected_masked" <<<"$leak_output"

# 3. Missing gitleaks binary fails with a clear message, not a raw crash.
missing_repo=$(make_repo missing-gitleaks)
if (
  cd "$missing_repo"
  PATH="/usr/bin:/bin" \
  SECRETS_SCAN_BASE=HEAD \
  "$scanner"
); then
  printf 'Expected a missing gitleaks binary to fail with a clear message.\n' >&2
  exit 1
fi

# 4. An unexpected gitleaks exit status is treated as a tool error, not a scan result.
status_repo=$(make_repo bad-status)
if (
  cd "$status_repo"
  PATH="$bin_dir:$PATH" \
  SECRETS_SCAN_BASE=HEAD \
  FAKE_GITLEAKS_EXIT=2 \
  "$scanner"
); then
  printf 'Expected an unexpected gitleaks exit status to fail the scan.\n' >&2
  exit 1
fi

# 5. No base ref and no origin remote fails with a clear message rather than guessing.
no_base_repo=$(make_repo no-base)
if (
  cd "$no_base_repo"
  PATH="$bin_dir:$PATH" \
  FAKE_GITLEAKS_EXIT=0 \
  "$scanner"
); then
  printf 'Expected scanning with no base and no origin remote to fail with a clear message.\n' >&2
  exit 1
fi

# 6. SECRETS_SCAN_STAGED=true invokes gitleaks protect --staged.
staged_repo=$(make_repo staged)
(
  cd "$staged_repo"
  PATH="$bin_dir:$PATH" \
  SECRETS_SCAN_STAGED=true \
  FAKE_GITLEAKS_REPORT='[]' \
  FAKE_GITLEAKS_EXIT=0 \
  "$scanner"
)
grep -Fq 'protect' "$staged_repo/gitleaks.args"
grep -Fq -- '--staged' "$staged_repo/gitleaks.args"
grep -Fq -- '--source .' "$staged_repo/gitleaks.args"
# --redact is the only thing preventing gitleaks' own console output from containing a raw secret.
grep -Fq -- '--redact' "$staged_repo/gitleaks.args"

# 7. Allowlist round-trip against the REAL gitleaks binary (not the shim): a known
#    dummy secret fails the scan, then adding it to .gitleaks.toml makes it pass.
#    This block intentionally does NOT put the fake gitleaks shim on PATH.
#    NOTE: this fixture deliberately does NOT use the AWS-documented example key
#    (AKIAIOSFODNN7EXAMPLE, used elsewhere in this repo's docs) — gitleaks' own
#    built-in default ruleset treats "EXAMPLE" as a stopword and never flags it,
#    so it can't prove the "before" half of this round-trip. AKIAABCDEFGHIJKLMNOP
#    is a sequential, obviously-synthetic value that still matches gitleaks' real
#    aws-access-token regex (which requires a [A-Z2-7]{16} suffix — no 0/1/8/9,
#    no lowercase), so it reliably triggers real detection.
if ! command -v gitleaks >/dev/null 2>&1; then
  printf 'SKIP: gitleaks not installed, skipping allowlist round-trip test.\n'
else
  allowlist_repo=$(make_repo allowlist)
  (
    cd "$allowlist_repo"
    printf 'aws_access_key_id = "AKIAABCDEFGHIJKLMNOP"\n' > secret.txt
    git add secret.txt
    git commit -qm 'add known dummy secret'
  )

  set +e
  allowlist_before_output=$(
    cd "$allowlist_repo"
    SECRETS_SCAN_BASE=HEAD~1 \
    "$scanner" 2>&1
  )
  allowlist_before_status=$?
  set -e
  if (( allowlist_before_status == 0 )); then
    printf 'Expected the known dummy secret to fail the scan before allowlisting.\n' >&2
    printf '%s\n' "$allowlist_before_output" >&2
    exit 1
  fi

  cat > "$allowlist_repo/.gitleaks.toml" <<'TOML'
[extend]
useDefault = true

[allowlist]
regexes = ['''AKIAABCDEFGHIJKLMNOP''']
TOML

  set +e
  allowlist_after_output=$(
    cd "$allowlist_repo"
    SECRETS_SCAN_BASE=HEAD~1 \
    "$scanner" 2>&1
  )
  allowlist_after_status=$?
  set -e
  if (( allowlist_after_status != 0 )); then
    printf 'Expected the scan to pass once the known dummy secret was allowlisted.\n' >&2
    printf '%s\n' "$allowlist_after_output" >&2
    exit 1
  fi

  printf 'PASS: allowlist round-trip against the real gitleaks binary confirmed.\n'
fi

printf 'PASS: gitleaks presence, range/staged modes, redaction, and error handling are enforced.\n'
