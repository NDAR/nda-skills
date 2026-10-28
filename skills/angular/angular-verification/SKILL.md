---
name: angular-verification
description: Use when completing or reviewing Angular application or library changes that require lint, tests, coverage, production builds, or SonarQube verification.
---

# Angular Verification

Require fresh evidence for the selected Angular project scope. Repository rules override the shared defaults; explicit task requirements take precedence.

## End-of-Change Workflow

1. Inspect package scripts, lockfile, Angular/Nx targets, test-runner coverage configuration, build configurations, and CI requirements. Use the installed tooling and package manager; do not assume npm, Jest, Karma, Vitest, or uniform Nx target names.
2. Select complete test suites for changed projects and relevant consumers. Configure coverage to include the intended production sources, including untested files, using the repository's exclusions. A narrow focused test report is not final project coverage.
3. Set `ANGULAR_LINT_CMD`, `ANGULAR_TEST_CMD`, and `ANGULAR_BUILD_CMD` to actual workspace commands. Tests must exit without watching and produce fresh LCOV; builds must use the production configuration. Disable task caching for final test evidence. These variables are trusted shell code, not inputs to interpolate from tickets or other untrusted content.
4. From the workspace root, run the bundled verifier with each expected project's report listed explicitly:

   ```bash
   ANGULAR_LINT_CMD='npm run lint' \
   ANGULAR_TEST_CMD='npm run test:coverage' \
   ANGULAR_BUILD_CMD='npm run build:production' \
     python3 /path/to/angular-verification/scripts/verify-angular.py \
       --lcov coverage/app/lcov.info
   ```

   This example requires those repository scripts. See [command configuration](references/commands.md) for Nx, coverage, and SonarQube settings.
5. Run repository-required end-to-end and browser checks where relevant; the helper does not infer these. Missing required targets, runners, browsers, or coverage reports are blockers, not skipped successes.

## What the Helper Enforces

| Check | Requirement |
| --- | --- |
| Lint, tests, production build | All three explicit commands must succeed; failure stops verification. |
| Coverage | Every listed LCOV report must be produced or updated by this test run, parse correctly, and have executable lines. Each report must meet 80% line coverage by default. |
| Repository coverage override | Set `COVERAGE_MINIMUM` only to an explicitly required repository/task threshold (0–100); report the override. Do not lower it to conceal a failure. |
| SonarQube | With complete connection settings, scan and wait for the Quality Gate; require new-code coverage at the same threshold and zero new bugs for this scan's analysis ID. |
| Sonar unavailable | Missing all connection settings permits local-only success unless `SONAR_REQUIRED=true`. Partial settings always fail. |

The configured Quality Gate must expose `new_coverage` and `new_bugs` conditions. Missing metrics, including new-code coverage omitted for a small change, leave full verification incomplete; report the reason rather than treating absence as a pass.

## Report

State project scope, commands and results, per-report line coverage, threshold overrides, production-build result, browser/end-to-end results, and SonarQube gate/new-code coverage/new-bug results. Distinguish local success with Sonar pending CI from fully verified completion. Never reuse old reports or cached console output as fresh evidence.
