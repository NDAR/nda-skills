# Secrets Credential Scanning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `secrets-credential-scanning` skill to `nda-skills` that wraps `gitleaks` to block commits/PRs containing non-allowlisted secrets, and wire it in as a required sub-skill of `codecommit-pr-merge` and `java-spring-harness`.

**Architecture:** A single bundled bash script (`scripts/scan-secrets.sh`) shells out to the `gitleaks` binary in one of two modes (committed range via `gitleaks detect --log-opts`, or staged changes via `gitleaks protect --staged`), then a `python3` step parses the JSON report, redacts any raw secret value, and turns findings into a nonzero exit. The `SKILL.md` tells the agent when/how to invoke it and how to react to a finding. Two existing skills gain an explicit `REQUIRED SUB-SKILL` line so this fires at the merge/completion choke points, not just on its own trigger description.

**Tech Stack:** bash, python3 (already required by `java-spring-verification`), gitleaks (external binary, not vendored).

## Global Constraints

- Folder name must match the skill `name` field exactly (`secrets-credential-scanning`).
- No absolute paths, tokens, account IDs, or personal home-directory paths in any committed skill content.
- Cross-stack skills live under `skills/common/`.
- Bump the `version` field in `.codex-plugin/plugin.json` (semver) on every skill change — this repo's distribution mechanism depends on the version bump to signal an update.
- Commit messages follow this repo's existing convention: `feat:` for new skill content, `docs:` for documentation-only changes (see `git log --oneline`).
- Never surface a raw matched secret value in any script output, report, or SKILL.md example — only masked/redacted forms.
- Do not install a git pre-commit hook into any consumer repo; this skill is agent-invoked, not a hook.

---

### Task 1: `scan-secrets.sh` script and its test

**Files:**
- Create: `skills/common/secrets-credential-scanning/scripts/scan-secrets.sh`
- Create: `skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh`

**Interfaces:**
- Consumes: `gitleaks` CLI (external binary on `PATH`), `python3` (external, on `PATH`).
- Produces: an executable script at `scripts/scan-secrets.sh` with this contract, which Task 2 (`SKILL.md`) and Tasks 3–4 (wiring) depend on:
  - Env vars: `SECRETS_SCAN_BASE` (optional base ref/commit), `SECRETS_SCAN_HEAD` (optional head ref/commit, defaults to `HEAD`), `SECRETS_SCAN_STAGED` (optional, `"true"` to scan staged changes instead of a commit range).
  - Exit `0` with `Secrets scan passed: no findings (<range>).` on stdout when clean.
  - Exit `1` with a per-finding line `  <file>:<line> rule=<rule> commit=<commit> secret=<masked>` on stdout when findings exist, secret value always masked.
  - Exit `1` via `Secrets scan failed: <reason>` on stderr for missing `gitleaks`/`python3`, an undetermined base branch, or an unexpected `gitleaks` exit status (not `0` or `1`).

- [ ] **Step 1: Write the failing test**

Create `skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh`:

```bash
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

printf 'PASS: gitleaks presence, range/staged modes, redaction, and error handling are enforced.\n'
```

- [ ] **Step 2: Make it executable and run it to verify it fails**

```bash
chmod +x skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh
skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh
```

Expected: fails immediately — `scripts/scan-secrets.sh` does not exist yet (e.g. `No such file or directory`).

- [ ] **Step 3: Write the implementation**

Create `skills/common/secrets-credential-scanning/scripts/scan-secrets.sh`:

```bash
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

python3 - "$report_path" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path) as handle:
        content = handle.read().strip()
except FileNotFoundError:
    content = ""

findings = json.loads(content) if content else []

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
```

```bash
chmod +x skills/common/secrets-credential-scanning/scripts/scan-secrets.sh
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh
```

Expected: `PASS: gitleaks presence, range/staged modes, redaction, and error handling are enforced.`

- [ ] **Step 5: Commit**

```bash
cd skills/common/secrets-credential-scanning 2>/dev/null; cd -
git add skills/common/secrets-credential-scanning/scripts/scan-secrets.sh \
        skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh
git commit -m "feat: add secrets scan script for secrets-credential-scanning skill"
```

---

### Task 2: `SKILL.md` and `agents/openai.yaml`

**Files:**
- Create: `skills/common/secrets-credential-scanning/SKILL.md`
- Create: `skills/common/secrets-credential-scanning/agents/openai.yaml`

**Interfaces:**
- Consumes: the `scripts/scan-secrets.sh` contract from Task 1 (env vars `SECRETS_SCAN_BASE`/`SECRETS_SCAN_HEAD`/`SECRETS_SCAN_STAGED`; exit 0/1 semantics).
- Produces: the skill name `secrets-credential-scanning`, referenced verbatim by Tasks 3 and 4's wiring edits.

- [ ] **Step 1: Write `SKILL.md`**

Create `skills/common/secrets-credential-scanning/SKILL.md`:

```markdown
---
name: secrets-credential-scanning
description: Use when about to commit, push, or open/merge a pull request in any repository, or when explicitly asked to scan for secrets. Blocks on any credential, API key, or private key found in the scanned range that is not explicitly allowlisted.
---

# Secrets & Credential Scanning

Scan a commit range or staged changes for secrets before they reach a shared branch. This is a hard gate: any non-allowlisted finding blocks the surrounding workflow (merge, push, completion) until resolved.

## Required Workflow

1. Run the bundled script from the target repository root:

   ```bash
   /path/to/secrets-credential-scanning/scripts/scan-secrets.sh
   ```

   The script itself checks that `gitleaks` is installed and stops with install instructions if it is missing — do not attempt to download or install `gitleaks` yourself.

   - When a specific base/head is already known (for example, a PR's `destinationCommit`/`sourceCommit`), set `SECRETS_SCAN_BASE` and `SECRETS_SCAN_HEAD` before running.
   - When scanning staged, not-yet-committed changes, set `SECRETS_SCAN_STAGED=true`.
   - With neither set, the script derives the base from the merge-base with the repo's default remote branch (`origin/HEAD`, `origin/main`, or `origin/master`).
2. If the script fails because no base could be derived, ask the human for the correct base ref (or the destination branch) rather than guessing.
3. On a finding:
   - Treat it as a real secret by default. Tell the human to rotate/revoke the credential immediately — the finding proves the secret is already in the scanned git range, so removing it in a later commit does not remove it from history.
   - Only treat it as a false positive if the human confirms it is not a real credential. In that case, add a narrowly-scoped entry (exact path or exact matched string, never a blanket rule disable) to a repo-root `.gitleaks.toml`, and note that this file change goes through the same PR review as any other code change.
   - Re-run the script after either rotation or an allowlist change.
4. Never repeat, quote, or forward the raw matched secret value in any report, commit message, PR comment, or chat message. The script already masks it in its own output; do not undo that by printing the underlying gitleaks JSON report file unmasked.

## Non-Goals

Do not install a git pre-commit hook into the target repository. This skill runs on demand — standalone, or as a required sub-skill of another workflow — not as an automatic git hook.

## Reporting

State the exact command run, the range or mode scanned, the finding count, and pass/fail. If findings are present, list file, line, rule, and commit per finding exactly as the script prints them (already redacted) — never add the raw secret back in.
```

- [ ] **Step 2: Write `agents/openai.yaml`**

Create `skills/common/secrets-credential-scanning/agents/openai.yaml`:

```yaml
interface:
  display_name: "Secrets & Credential Scanning"
  short_description: "Scan a diff for leaked secrets before merge"
  default_prompt: "Use $secrets-credential-scanning to scan the current change for committed secrets before merging or pushing."
```

- [ ] **Step 3: Verify folder/name match and file placement**

```bash
test -f skills/common/secrets-credential-scanning/SKILL.md
test -f skills/common/secrets-credential-scanning/agents/openai.yaml
grep -q '^name: secrets-credential-scanning$' skills/common/secrets-credential-scanning/SKILL.md
```

Expected: all three commands succeed silently (no output, exit 0).

- [ ] **Step 4: Commit**

```bash
git add skills/common/secrets-credential-scanning/SKILL.md \
        skills/common/secrets-credential-scanning/agents/openai.yaml
git commit -m "feat: add secrets-credential-scanning skill"
```

---

### Task 3: Wire into `codecommit-pr-merge`

**Files:**
- Modify: `skills/common/codecommit-pr-merge/SKILL.md:12-21` (Operating Rules), `:42-56` (Review Changes)

**Interfaces:**
- Consumes: skill name `secrets-credential-scanning` and its `SECRETS_SCAN_BASE`/`SECRETS_SCAN_HEAD` env vars from Task 1/2.

- [ ] **Step 1: Add an Operating Rule**

In `skills/common/codecommit-pr-merge/SKILL.md`, in the `## Operating Rules` section, change:

```markdown
- Never merge if approval rules are unsatisfied; report the blocker and pause.
```

to:

```markdown
- Never merge if approval rules are unsatisfied; report the blocker and pause.
- Never merge if `secrets-credential-scanning` reports a blocking, non-allowlisted finding for the PR's commit range.
```

- [ ] **Step 2: Require the scan in the Review Changes workflow**

In the same file, in `## Review Changes`, change:

```markdown
Review changed files directly. For code-review requests, lead with findings ordered by severity. If no blocking issues are found, say so and include verification evidence.

Run the appropriate project verification command before recommending merge. Prefer the full test command when practical.
```

to:

```markdown
Review changed files directly. For code-review requests, lead with findings ordered by severity. If no blocking issues are found, say so and include verification evidence.

**REQUIRED SUB-SKILL:** Use `secrets-credential-scanning` with `SECRETS_SCAN_BASE=<destinationCommit>` and `SECRETS_SCAN_HEAD=<sourceCommit>` before recommending merge. A blocking, non-allowlisted finding pauses the merge until the human resolves it.

Run the appropriate project verification command before recommending merge. Prefer the full test command when practical.
```

- [ ] **Step 3: Verify the edits**

```bash
grep -c 'secrets-credential-scanning' skills/common/codecommit-pr-merge/SKILL.md
```

Expected: `2`.

- [ ] **Step 4: Commit**

```bash
git add skills/common/codecommit-pr-merge/SKILL.md
git commit -m "feat: require secrets-credential-scanning before CodeCommit PR merge"
```

---

### Task 4: Wire into `java-spring-harness`

**Files:**
- Modify: `skills/java-springboot/java-spring-harness/SKILL.md:10-20` (Required Workflow)

**Interfaces:**
- Consumes: skill name `secrets-credential-scanning` from Task 1/2.

- [ ] **Step 1: Insert a new required step before verification**

In `skills/java-springboot/java-spring-harness/SKILL.md`, change:

```markdown
4. Run the repository's fast, relevant checks while iterating. Follow service-specific commands where supplied.
5. Before reporting completion, explicitly invoke `java-spring-verification`, then run its verification script from the target service root.
6. Report only fresh evidence: commands run, Maven result, JaCoCo coverage, SonarQube Quality Gate/new-code coverage/new-bug results when configured, and every unavailable or failing required check.
```

to:

```markdown
4. Run the repository's fast, relevant checks while iterating. Follow service-specific commands where supplied.
5. **REQUIRED SUB-SKILL:** Use `secrets-credential-scanning` against the working diff before invoking `java-spring-verification`. A blocking, non-allowlisted finding must be resolved — credential rotation or a reviewed `.gitleaks.toml` entry — before continuing.
6. Before reporting completion, explicitly invoke `java-spring-verification`, then run its verification script from the target service root.
7. Report only fresh evidence: commands run, Maven result, JaCoCo coverage, SonarQube Quality Gate/new-code coverage/new-bug results when configured, and every unavailable or failing required check.
```

- [ ] **Step 2: Verify the edit**

```bash
grep -q 'REQUIRED SUB-SKILL:\*\* Use `secrets-credential-scanning`' skills/java-springboot/java-spring-harness/SKILL.md
```

Expected: exit 0 (match found).

- [ ] **Step 3: Commit**

```bash
git add skills/java-springboot/java-spring-harness/SKILL.md
git commit -m "feat: require secrets-credential-scanning in Java Spring harness"
```

---

### Task 5: Version bump and README documentation

**Files:**
- Modify: `.codex-plugin/plugin.json:3`
- Modify: `README.md` (insert new section after the "Java/Spring verification and SonarQube" section, before "## Repository layout")

**Interfaces:** none (terminal task; no later task depends on this one).

- [ ] **Step 1: Bump the plugin version**

In `.codex-plugin/plugin.json`, change:

```json
  "version": "0.9.0",
```

to:

```json
  "version": "0.10.0",
```

- [ ] **Step 2: Add the README section**

In `README.md`, insert this new section immediately after the existing `## Java/Spring verification and SonarQube` section (i.e., right before `## Repository layout`):

```markdown
## Secrets scanning (gitleaks)

The `secrets-credential-scanning` skill wraps [gitleaks](https://github.com/gitleaks/gitleaks) and is wired as a required sub-skill of `codecommit-pr-merge` and `java-spring-harness`. Install gitleaks locally before those workflows run (`brew install gitleaks`, or download a release binary) — the skill does not install it for you.

To allowlist a confirmed false positive (for example, a documented example key used only in a test fixture), add a narrowly-scoped entry to a repo-root `.gitleaks.toml` and get it reviewed like any other code change:

\`\`\`toml
[allowlist]
paths = [
  '''tests/fixtures/.*''',
]
regexes = [
  '''AKIAIOSFODNN7EXAMPLE''',
]
\`\`\`

Never widen an allowlist entry beyond the specific known-fake value or path it covers.
```

- [ ] **Step 3: Verify**

```bash
grep -q '"version": "0.10.0"' .codex-plugin/plugin.json
grep -q '## Secrets scanning (gitleaks)' README.md
```

Expected: both exit 0.

- [ ] **Step 4: Run the full skill test suite as a final sanity check**

```bash
skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh
skills/java-springboot/java-spring-verification/tests/verify-java-service-test.sh
```

Expected: both print their `PASS:` line.

- [ ] **Step 5: Commit**

```bash
git add .codex-plugin/plugin.json README.md
git commit -m "docs: document gitleaks prerequisite and bump plugin version"
```
