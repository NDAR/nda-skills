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
   - Only treat it as a false positive if the human confirms it is not a real credential. In that case, add a narrowly-scoped entry (exact path or exact matched string, never a blanket rule disable) to a repo-root `.gitleaks.toml`, and note that this file change goes through the same PR review as any other code change. gitleaks *replaces* its embedded default ruleset with whatever config it loads, so any `.gitleaks.toml` you create or edit must start with `[extend]` / `useDefault = true` before the `[allowlist]` block — without it, the file silently disables all default detection rules (see the README's "Secrets scanning (gitleaks)" section for a full example).
   - Re-run the script after either rotation or an allowlist change.
4. Never repeat, quote, or forward the raw matched secret value in any report, commit message, PR comment, or chat message. The script already masks it in its own output; do not undo that by printing the underlying gitleaks JSON report file unmasked.

## Non-Goals

Do not install a Git pre-commit hook into the target repository. The plugin instead bundles a Codex `PreToolUse` hook that, once the user trusts it, scans Codex-issued `git commit` and `git push` commands before they run. It does not apply to Git commands run outside Codex and is not a substitute for CI enforcement.

This skill remains the manual and workflow-level interface: use it to scan a specific PR range, an explicitly staged change, or any change that was not initiated by the Codex Git-command hook.

## Reporting

State the exact command run, the range or mode scanned, the finding count, and pass/fail. If findings are present, list file, line, rule, and commit per finding exactly as the script prints them (already redacted) — never add the raw secret back in.
