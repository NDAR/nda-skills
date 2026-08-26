# Secrets-Scanning Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block Codex-initiated Git commits and pushes when the NDA gitleaks scanner finds a credential or cannot complete its scan.

**Architecture:** Bundle a `PreToolUse` `Bash` hook in the plugin. Its wrapper reads Codex's JSON event from standard input, ignores non-Git commands, and runs the established scanner from the target repository root before commit or push commands; exit status 2 denies the requested tool call.

**Tech Stack:** Codex hooks JSON, Bash, Python 3 standard library, gitleaks v8.x.

---

### Task 1: Add failing wrapper tests

**Files:**
- Create: `hooks/scripts/pre-git-secrets-scan.sh`
- Create: `hooks/tests/pre-git-secrets-scan-test.sh`

- [ ] **Step 1: Write tests with a fake scanner**

Exercise a clean staged commit, a scanner finding, a scanner tool error, a push range scan, and a non-Git command. Assert that only commit and push inputs invoke the scanner and that scanner failures write a Codex block response to standard output and exit 2.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash hooks/tests/pre-git-secrets-scan-test.sh`

Expected: FAIL because the wrapper does not exist.

### Task 2: Implement the pre-Git-command wrapper

**Files:**
- Create: `hooks/scripts/pre-git-secrets-scan.sh`
- Test: `hooks/tests/pre-git-secrets-scan-test.sh`

- [ ] **Step 1: Parse the hook input safely**

Use Python 3's JSON parser to read `tool_input.command` and `cwd`; treat malformed input or a missing command as a no-op.

- [ ] **Step 2: Recognize only Git commit and push commands**

Match Git subcommands without executing or interpolating the user-provided command. Run staged scanning for commits and the scanner's default branch-range mode for pushes.

- [ ] **Step 3: Run the existing scanner from the target Git root**

Locate the root with `git -C "$cwd" rev-parse --show-toplevel`; invoke `$PLUGIN_ROOT/skills/common/secrets-credential-scanning/scripts/scan-secrets.sh` from that root. On any non-zero scan result, emit the supported `PreToolUse` deny JSON and exit 2 without echoing a raw secret.

- [ ] **Step 4: Run the wrapper test**

Run: `bash hooks/tests/pre-git-secrets-scan-test.sh`

Expected: PASS for clean, finding, tool-error, push, and no-op cases.

### Task 3: Package and document the hook

**Files:**
- Create: `hooks/hooks.json`
- Modify: `.codex-plugin/plugin.json`
- Modify: `README.md`
- Modify: `skills/common/secrets-credential-scanning/SKILL.md`

- [ ] **Step 1: Register the plugin hook**

Point the manifest's `hooks` field to `./hooks/hooks.json`. Configure a synchronous `PreToolUse` handler for `Bash`, use `${PLUGIN_ROOT}` to locate the wrapper, set a 120-second timeout, and state the hook's status message.

- [ ] **Step 2: Update behavior documentation**

Document the trusted hook review requirement, that it gates Codex-issued Git commit/push commands only, and that the skill remains the manual/PR workflow scanner. Remove the obsolete statement that automatic hook execution is a non-goal while retaining the rule against installing Git hooks in target repositories.

- [ ] **Step 3: Bump the plugin version**

Change version `0.10.0` to `0.11.0`.

### Task 4: Verify the release artifact

**Files:**
- Test: `hooks/tests/pre-git-secrets-scan-test.sh`
- Test: `skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh`

- [ ] **Step 1: Run both test suites**

Run: `bash hooks/tests/pre-git-secrets-scan-test.sh && bash skills/common/secrets-credential-scanning/tests/scan-secrets-test.sh`

Expected: both tests pass; the second may report that its optional real-gitleaks allowlist round-trip is skipped when gitleaks is unavailable.

- [ ] **Step 2: Validate JSON and whitespace**

Run: `jq empty .codex-plugin/plugin.json hooks/hooks.json && git diff --check`

Expected: valid JSON and no whitespace errors in tracked changes.
