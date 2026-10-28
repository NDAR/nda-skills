# nda-skills

Shared Codex skills for the NDA team, distributed as a Codex plugin marketplace.

One repo, many consumers: skills live here, and developers install them from this marketplace with Codex CLI. Updates propagate to the team with a single command. The current skills cover shared workflows, Java/Spring, and Angular code; Codex selects stack-specific skills by their descriptions.

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

| Variable            | Purpose                                                                                                                                        |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `SONAR_HOST_URL`    | URL of the SonarQube server.                                                                                                                   |
| `SONAR_TOKEN`       | Token authorized to run analysis and read the Quality Gate. Store it only in the CI secret store or local environment; never commit or log it. |
| `SONAR_PROJECT_KEY` | SonarQube project key for the service.                                                                                                         |

Set `SONAR_REQUIRED=true` in CI when SonarQube validation is mandatory. This makes the verification fail if the required SonarQube variables are missing, rather than skipping SonarQube. If only some of the three SonarQube variables are set, verification also fails so a misconfigured analysis cannot be silently skipped.

For pull-request analysis, also set `SONAR_PULL_REQUEST_KEY`, `SONAR_PULL_REQUEST_BRANCH`, and `SONAR_PULL_REQUEST_BASE`. For branch analysis, set `SONAR_BRANCH_NAME` instead. The configured SonarQube Quality Gate must require new-code coverage of at least 80% and zero new bugs.

## Angular development and verification

The Angular set mirrors the Java/Spring structure:

| Skill                      | Purpose                                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `angular-coding-standards` | Repository-first conventions for Angular/TypeScript, components, templates, state, accessibility, and tests.             |
| `angular-harness`          | Coordinate TDD, command discovery, fast checks, review, and completion checks in Angular CLI or Nx workspaces.           |
| `angular-verification`     | Run lint, full tests for the selected projects, fresh LCOV coverage, production builds, and configured SonarQube checks. |

Use `$angular-harness` for an Angular change. The skills honor the installed Angular version, package manager, and test runner; they do not require migrations to newer APIs or tooling.

The fast-check helper requires `FORMAT_CHECK_CMD`, `ANGULAR_LINT_CMD`, and `TEST_TOUCHED_CMD`. Final verification requires `ANGULAR_LINT_CMD`, `ANGULAR_TEST_CMD`, and `ANGULAR_BUILD_CMD`, plus explicit `--lcov` paths. Commands must be selected from the target workspace; the helpers do not guess Nx targets or start watch-mode tests. Invoke the helpers with `bash` and `python3`, respectively.

Each expected coverage report must be fresh and meet **80% line coverage** by default. `COVERAGE_MINIMUM` supports explicit repository/task overrides, which must be reported. SonarQube uses the same connection and analysis-context variables described for Java above, plus an installed SonarScanner CLI. Its gate must expose new-code coverage and new-bug conditions. Set `SONAR_REQUIRED=true` in CI to make absent credentials fail; partial connection settings always fail. Local-only success explicitly leaves Sonar verification pending.

See [Angular verification](skills/angular/angular-verification/SKILL.md) and its [command configuration](skills/angular/angular-verification/references/commands.md) for examples, prerequisites, and limitations.

## Secrets scanning (gitleaks)

The `secrets-credential-scanning` skill wraps [gitleaks](https://github.com/gitleaks/gitleaks) and is wired as a required sub-skill of `codecommit-pr-merge` and `java-spring-harness`. Install gitleaks locally before those workflows run (`brew install gitleaks`, or download a release binary) — the skill does not install it for you.

The scanner script is written against gitleaks' `detect` and `protect` subcommands (v8.x). If a future major gitleaks version renames or removes those subcommands, the scan itself will fail to produce a report, and the script's report-file check turns that into a loud, visible scan failure rather than a silent false pass.

### Codex lifecycle hooks

Version `0.14.0` bundles Codex `PreToolUse` hooks. After installing or upgrading the plugin, review and trust the hooks with `/hooks`; Codex skips a new or changed plugin hook until it has been trusted. The hooks match Codex Git commands issued through `Bash` and include an `exec` compatibility matcher for hosts that expose unified execution with that tool name:

- Before `git commit`, it scans staged changes with `gitleaks protect --staged`.
- Before `git push`, it scans the current branch range using the scanner's established default-base resolution.
- A finding, missing `gitleaks`, or scanner failure blocks that Codex Git command. The hook intentionally suppresses scanner output so it cannot pass a matched secret back into the model context.
- Before `git commit` in a Maven repository, it checks direct parent, dependency, and build-plugin versions for stable updates in the root POM and every reactor module declared through `<modules>`. It excludes profiles, dependency management, and plugin management.
- Available updates block the commit and show Codex the report. Codex must ask whether to update the POM or defer it. Only after explicit user approval may Codex retry using `git -c nda.pom-update-check.override=<reason> commit ...`.
- A Maven checker or metadata-resolution failure also blocks the commit; it is not treated as proof that the POM is current.

The hooks cover Git commands issued by Codex only. They do not install Git hooks in target repositories, scan Git commands run outside Codex, or replace required CI/PR checks. Use `$secrets-credential-scanning` for manual scans and PR-range scans.

To allowlist a confirmed false positive (for example, a documented example key used only in a test fixture), add a narrowly-scoped entry to a repo-root `.gitleaks.toml` and get it reviewed like any other code change. gitleaks _replaces_ its embedded default ruleset with whatever config it loads from the source root, so the `[extend]` block below is required to keep gitleaks' built-in detection rules active — without it, a custom `.gitleaks.toml` silently disables all default rules and the scan would stop detecting anything:

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

### Local environment for the agent

Export the service settings in the environment used to launch the agent (or inject them into its runtime through your secret manager):

```bash
export SONAR_HOST_URL='https://your-sonarqube-server'
export SONAR_PROJECT_KEY='your-service-key'
export SONAR_BRANCH_NAME='your-feature-branch'
unset SONAR_PULL_REQUEST_KEY SONAR_PULL_REQUEST_BRANCH SONAR_PULL_REQUEST_BASE
```

Also export `SONAR_TOKEN` securely through your local secret-management setup. It must be authorized to submit analyses and read results. Do not paste the token into a chat, command argument, committed file, or log. Only `SONAR_TOKEN` is recognized; `SONAR_CODEX_TOKEN` is not supported.

The agent's command-running process must inherit these exported variables. Start a new agent process from the configured environment if the existing one does not have them; setting a variable in another terminal does not update an already-running process. Keep project and branch settings specific to the service being analyzed.

For a pull request, replace the branch selection with the complete tuple:

```bash
unset SONAR_BRANCH_NAME
export SONAR_PULL_REQUEST_KEY='42'
export SONAR_PULL_REQUEST_BRANCH='your-feature-branch'
export SONAR_PULL_REQUEST_BASE='main'
```

### SonarQube new-code sensor

`sonar-new-code` is the focused command-line companion to the IDE's **Focus on New Code** view. It runs a Maven SonarQube branch or pull-request analysis, waits for the Quality Gate, and reports new-code metrics without printing the token. Use `java-spring-verification` when Maven and JaCoCo verification are also required.

Run the sensor from the target service's Maven project root after tests have generated its coverage report:

```bash
/path/to/nda-skills/skills/java-springboot/sonar-new-code/scripts/check-sonar-new-code.sh
```

The path may point directly to a local checkout or worktree to test changes before merge. Ask the agent to use `sonar-new-code` for a focused report, or `java-spring-verification` for the full Maven and coverage workflow. The sensor requires access to the configured SonarQube server, Maven (or `./mvnw`), `curl`, and `python3`.

The sensor rejects incomplete pull-request tuples before scanning. If no context variables are supplied, it uses the current Git branch. Its report includes the submitted analysis's Quality Gate and new-code metrics; missing measurements appear as `N/A`. A completed analysis with a failed gate still prints metrics and exits nonzero. Scanner failures also exit nonzero. Gate queries are tied to the current analysis ID; metric queries read the latest values for the selected project/context.

## Repository layout

```
.agents/plugins/marketplace.json   # marketplace descriptor (do not rename/move)
.codex-plugin/plugin.json          # plugin manifest — bump "version" on every change
skills/
  common/                          # cross-stack skills (PR/commit workflow, etc.)
  java-springboot/                 # Java and Spring conventions
  angular/                         # Angular CLI and Nx conventions and checks
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
