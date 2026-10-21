---
name: angular-harness
description: Use when creating, changing, reviewing, testing, or completing Angular application or library changes in Angular CLI or Nx workspaces.
---

# Angular Harness

Coordinate Angular standards, iteration, and final verification. Repository instructions remain authoritative; this skill does not install hooks or alter workspace configuration automatically.

## Required Workflow

1. Explicitly invoke `angular-coding-standards` before editing Angular production or test code. Inspect repository instructions, installed Angular/Node/package-manager versions, lockfiles, scripts, Angular builders or Nx executors, and adjacent tests.
2. **REQUIRED SUB-SKILL:** Use `pair-programming-tdd` for production behavior changes. Follow its story-slice checkpoints, subject to the user's explicit workflow instructions. For read-only reviews, inspect evidence without manufacturing edits or staging files.
3. Use the applicable Superpowers skills when installed: `superpowers:test-driven-development` for features/fixes, `superpowers:systematic-debugging` for failures, and `superpowers:requesting-code-review` after material implementation changes. If unavailable, retain the equivalent test-first, diagnosis, and review steps; do not claim invocation.
4. Choose actual workspace commands before running checks. Use the pinned package manager and local executables. In Nx, inspect each selected project's targets, executor options, and dependencies; include affected consumers for shared-library changes. Establish the comparison base explicitly when using affected selection. Include uncommitted changes in local scope; do not assume `HEAD` captures them.
5. Run the bundled fast-check script from the workspace root:

   ```bash
   FORMAT_CHECK_CMD='npm run format:check' \
   ANGULAR_LINT_CMD='npm run lint' \
   TEST_TOUCHED_CMD='npm run test:focused' \
     bash /path/to/angular-harness/scripts/run-fast-checks.sh
   ```

   This is an example for a repository defining those scripts. Substitute verified commands; the helper requires all three and never invents targets. Choose a non-writing formatting check and a non-watch focused test command. It stops at the first failure and checks working-tree and staged whitespace without staging or formatting files.
6. Before commit, push, or PR actions, use `secrets-credential-scanning` with the correct staged or branch scope. Stage only task files when staging is part of the authorized workflow. Do not sweep unrelated changes into the index.
7. Explicitly invoke `angular-verification` before reporting completion. Run full tests for the selected project scope, coverage, lint, and production builds. Verify relevant browser interactions/accessibility and configured end-to-end checks for UI changes. Fast focused tests alone are not final verification.

## Command Selection and Reporting

| Situation | Action |
| --- | --- |
| Root test command watches or targets everything | Select the project's real executor and supported non-watch options. |
| Missing target or tool | Report the missing check; do not replace it with a no-op or install/migrate tooling incidentally. |
| Cached test result | For final evidence, disable task caching using options supported by the installed Nx version; generate fresh coverage. |
| Unrelated local edits | Preserve them, including the existing index. |

Report changed behavior, resolved repository overrides, project scope, exact commands/results, coverage by project, browser checks, and SonarQube status or blockers. Skills coordinate behavior; CI and workspace tooling enforce configured policies.

For Nx details, consult [running tasks](https://nx.dev/docs/features/run-tasks), [affected selection](https://nx.dev/docs/features/ci-features/affected), and [skipping cache](https://nx.dev/docs/kb/skipping-cache) for the installed version.
