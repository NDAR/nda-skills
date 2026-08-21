# nda-skills

Shared Codex skills for the NDA team, distributed as a Codex plugin marketplace.

One repo, many consumers: skills live here, and developers install them from this marketplace with Codex CLI. Updates propagate to the team with a single command. The current skills cover shared workflows and Java/Spring code; Codex triggers each skill by its description, so a Java skill simply will not fire while working in an unrelated repository.

## Prerequisites

You need working **HTTPS** git credentials for GitHub before installing. Codex delegates authentication to git itself, so if you can `git clone` a private NDA repo over HTTPS, the marketplace install will work the same way.

Confirm it reaches the repo non-interactively:

```bash
git ls-remote https://github.com/NDAR/nda-skills.git
```

If that lists refs without prompting, you're set. If it prompts or fails, fix your HTTPS git auth first (a personal access token in your credential helper, or the `gh` CLI configured) — the plugin commands can't authenticate any better than plain git can.

> Note: SSH (`git@github.com:...`) is **not** assumed to be set up. Use the HTTPS URL throughout, exactly as shown below.

## Install (one time)

Register the marketplace and install the plugin:

```bash
codex plugin marketplace add https://github.com/NDAR/nda-skills.git --ref main
codex plugin add nda-skills@nda-skills
```

Then restart Codex. Verify the plugin is installed and enabled:

```bash
codex plugin list
```

You should see `nda-skills@nda-skills` with status `installed, enabled`.

### Skill UI metadata

An optional `agents/openai.yaml` supplies product-specific UI metadata, such as a display name, short description, and default invocation prompt. It does not define an agent or control runtime trust prompts.

## Updating (whenever skills change)

When new skills are added or existing ones are updated on `main`, pull the latest with a single command:

```bash
codex plugin marketplace upgrade
```

This refreshes the marketplace snapshot and moves your installed plugin to the new version in one step — no reinstall needed. Restart Codex (or start a new session) for the updated skills to take effect. Confirm the version bumped with `codex plugin list`.

## Pair-programming TDD

For requests that create, change, or fix production behavior, NDA Skills works one independently testable story slice at a time. The agent writes and runs a failing test, makes the smallest change to pass it, refactors only while tests remain green, and then reports the evidence. It waits for explicit human approval before beginning the next slice.

## Java/Spring verification and SonarQube

The `java-spring-verification` skill always runs Maven and checks JaCoCo line coverage. To enable its SonarQube validation, provide all of the following variables to the agent or CI-job environment for the target service:

| Variable | Purpose |
| --- | --- |
| `SONAR_HOST_URL` | URL of the SonarQube server. |
| `SONAR_TOKEN` | Token authorized to run analysis and read the Quality Gate. Store it only in the CI secret store or local environment; never commit or log it. |
| `SONAR_PROJECT_KEY` | SonarQube project key for the service. |

Set `SONAR_REQUIRED=true` in CI when SonarQube validation is mandatory. This makes the verification fail if the required SonarQube variables are missing, rather than skipping SonarQube. If only some of the three SonarQube variables are set, verification also fails so a misconfigured analysis cannot be silently skipped.

For pull-request analysis, also set `SONAR_PULL_REQUEST_KEY`, `SONAR_PULL_REQUEST_BRANCH`, and `SONAR_PULL_REQUEST_BASE`. For branch analysis, set `SONAR_BRANCH_NAME` instead. The configured SonarQube Quality Gate must require new-code coverage of at least 80% and zero new bugs.

## Secrets scanning (gitleaks)

The `secrets-credential-scanning` skill wraps [gitleaks](https://github.com/gitleaks/gitleaks) and is wired as a required sub-skill of `codecommit-pr-merge` and `java-spring-harness`. Install gitleaks locally before those workflows run (`brew install gitleaks`, or download a release binary) — the skill does not install it for you.

The scanner script is written against gitleaks' `detect` and `protect` subcommands (v8.x). If a future major gitleaks version renames or removes those subcommands, the scan itself will fail to produce a report, and the script's report-file check turns that into a loud, visible scan failure rather than a silent false pass.

### Codex lifecycle hook

Version `0.11.0` bundles a Codex `PreToolUse` hook. After installing or upgrading the plugin, review and trust the hook with `/hooks`; Codex skips a new or changed plugin hook until it has been trusted. The hook runs before Codex issues a Bash `git commit` or `git push` command:

- Before `git commit`, it scans staged changes with `gitleaks protect --staged`.
- Before `git push`, it scans the current branch range using the scanner's established default-base resolution.
- A finding, missing `gitleaks`, or scanner failure blocks that Codex Git command. The hook intentionally suppresses scanner output so it cannot pass a matched secret back into the model context.

The hook covers Git commands issued by Codex only. It does not install a Git hook in target repositories, scan Git commands run outside Codex, or replace required CI/PR checks. Use `$secrets-credential-scanning` for manual scans and PR-range scans.

To allowlist a confirmed false positive (for example, a documented example key used only in a test fixture), add a narrowly-scoped entry to a repo-root `.gitleaks.toml` and get it reviewed like any other code change. gitleaks *replaces* its embedded default ruleset with whatever config it loads from the source root, so the `[extend]` block below is required to keep gitleaks' built-in detection rules active — without it, a custom `.gitleaks.toml` silently disables all default rules and the scan would stop detecting anything:

```toml
[extend]
useDefault = true

[allowlist]
paths = [
  '''tests/fixtures/.*''',
]
regexes = [
  '''AKIAIOSFODNN7EXAMPLE''',
]
```

Never widen an allowlist entry beyond the specific known-fake value or path it covers.

## Repository layout

```
.agents/plugins/marketplace.json   # marketplace descriptor (do not rename/move)
.codex-plugin/plugin.json          # plugin manifest — bump "version" on every change
skills/
  common/                          # cross-stack skills (PR/commit workflow, etc.)
  java-springboot/                 # Java and Spring conventions
```

Skills are grouped into folders by stack for maintenance clarity. Codex scans nested folders under `skills/`, so grouping does not affect discovery — a skill fires based on its description regardless of which folder it lives in. The folders are for our own navigation.

## Authoring a skill

A skill is a folder containing a `SKILL.md` with YAML frontmatter, optionally plus an `agents/` folder and supporting files.

Minimal `SKILL.md`:

```markdown
---
name: my-skill-name
description: Use whenever <clear triggering condition>. Describe precisely
  when this should fire — Codex matches on this text to decide when to load it.
---

# My Skill Name

<Instructions the agent follows when the skill triggers.>
```

Conventions to follow:

- **Folder name must match the skill `name`.** If a skill or its agent is invoked as `$my-skill-name`, the folder must be `my-skill-name`. A mismatch breaks the reference.
- **Write the description as a trigger, not a summary.** It decides when the skill fires. Be specific about the condition ("Use when writing or editing Spring Boot controllers") rather than vague ("Spring Boot helper").
- **Keep skills free of machine- or account-specific values.** No absolute paths, tokens, account IDs, or personal home-directory paths — anything committed here ships to every teammate. Trust settings and local config stay on each machine, not in the repo.
- **Put cross-stack skills in `common/`** and stack-specific ones in their stack folder.

## Contributing changes

Skills are captured and propagated with ordinary git:

1. While working in any repo, when you refine or add a skill, make the change in a branch of this repo (a git worktree keeps it isolated from the repo you're actively working in).
2. Add or edit the skill under the appropriate `skills/` subfolder.
3. **Bump the `version` field in `.codex-plugin/plugin.json`** (semver — e.g. `0.3.0` → `0.4.0`). This gives `codex plugin list` and `marketplace upgrade` a meaningful version to report; without a bump, teammates can't easily tell whether they have the latest.
4. Open a PR into `main`.
5. On merge, every teammate picks it up on their next `codex plugin marketplace upgrade`.

That's the whole distribution loop: merge to `main` = live for the team on next upgrade. No manual copying between repos, no separate distribution step.

## Quick reference

| Task                 | Command                                                                                                                        |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Check git auth       | `git ls-remote https://github.com/NDAR/nda-skills.git`                                                                         |
| Install (first time) | `codex plugin marketplace add https://github.com/NDAR/nda-skills.git --ref main` then `codex plugin add nda-skills@nda-skills` |
| Update to latest     | `codex plugin marketplace upgrade`                                                                                             |
| Check status/version | `codex plugin list`                                                                                                            |
| Remove plugin        | `codex plugin remove nda-skills@nda-skills`                                                                                    |
| Remove marketplace   | `codex plugin marketplace remove nda-skills`                                                                                   |
