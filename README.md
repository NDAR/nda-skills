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

## Java/Spring verification and SonarQube

The `java-spring-verification` skill always runs Maven and checks JaCoCo line coverage. To enable its SonarQube validation, provide all of the following variables to the agent or CI-job environment for the target service:

| Variable | Purpose |
| --- | --- |
| `SONAR_HOST_URL` | URL of the SonarQube server. |
| `SONAR_TOKEN` | Token authorized to run analysis and read the Quality Gate. Store it only in the CI secret store or local environment; never commit or log it. |
| `SONAR_PROJECT_KEY` | SonarQube project key for the service. |

Set `SONAR_REQUIRED=true` in CI when SonarQube validation is mandatory. This makes the verification fail if the required SonarQube variables are missing, rather than skipping SonarQube. If only some of the three SonarQube variables are set, verification also fails so a misconfigured analysis cannot be silently skipped.

For pull-request analysis, also set `SONAR_PULL_REQUEST_KEY`, `SONAR_PULL_REQUEST_BRANCH`, and `SONAR_PULL_REQUEST_BASE`. For branch analysis, set `SONAR_BRANCH_NAME` instead. The configured SonarQube Quality Gate must require new-code coverage of at least 80% and zero new bugs.

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
