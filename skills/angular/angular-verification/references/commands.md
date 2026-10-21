# Angular verification command configuration

Run helpers from the target workspace root. Python 3 is required for final verification; Bash and Git are required for fast checks. Dependencies and the appropriate Node/package-manager version must already be available. Helpers do not install dependencies, infer target names, rewrite configuration, stage files, or run a dependency audit automatically.

## Select commands from the repository

Read `package.json` scripts, `packageManager` and engine declarations, lockfiles, `angular.json` or Nx project targets, and the test runner configuration. Match flags to the installed executor. For example, a Karma builder and a newer Vitest builder can expose different coverage options; do not copy flags from current Angular documentation into an older workspace without checking support.

For Nx, inspect resolved targets using the installed Nx CLI where available. A project may inherit targets rather than declare them directly in `project.json`. Verify the base/head and local change scope before using affected selection, and include dependent consumers for shared-library changes. If the comparison base is unavailable, use an explicit reviewed project list or report the blocker.

Example only for an npm/Nx workspace where `portal` defines these targets and uses a Jest test executor:

```bash
ANGULAR_LINT_CMD='npm exec -- nx run portal:lint --skip-nx-cache' \
ANGULAR_TEST_CMD='npm exec -- nx run portal:test --watch=false --coverage --skip-nx-cache' \
ANGULAR_BUILD_CMD='npm exec -- nx run portal:build:production --skip-nx-cache' \
  python3 /path/to/angular-verification/scripts/verify-angular.py \
    --lcov coverage/apps/portal/lcov.info
```

Use the repository's pnpm/yarn commands when applicable. Ensure local dependencies exist before using a package-manager launcher; do not let it download an unpinned CLI. For multiple projects, compose the real commands and repeat `--lcov` for every expected report. Every report is checked separately; unrelated high-coverage projects cannot hide a failing selected project. A combined report is only appropriate when the repository defines that combined coverage scope.

The LCOV parser uses `DA` line records, validates `LF`/`LH` summaries when present, and merges repeated source/line identities. It does not establish that all relevant source files were instrumented: inspect the runner's source inclusion/exclusion configuration. Reports must change during the test command. Disable cache reuse, and do not touch or copy old reports to satisfy freshness. The helper preserves existing reports and detects unchanged ones rather than deleting coverage directories.

`FORMAT_CHECK_CMD` and `TEST_TOUCHED_CMD` apply only to the harness fast-check helper. `ANGULAR_LINT_CMD` is shared by both helpers. Prefer check-only formatting; avoid whole-workspace rewrites.

## SonarQube

| Variable | Meaning |
| --- | --- |
| `SONAR_HOST_URL` | HTTPS server URL; HTTP is accepted only for localhost testing. |
| `SONAR_TOKEN` | Environment-only authentication token, never committed or included in command arguments. |
| `SONAR_PROJECT_KEY` | Project configured for the selected source/coverage scope. |
| `SONAR_REQUIRED` | `true` makes missing connection settings fail; default `false` permits local-only checks. |
| `SONAR_SCANNER` | Scanner executable name/path; defaults to `sonar-scanner`. Not a shell command or argument string. |
| `SONAR_QUALITY_GATE_TIMEOUT` | Positive integer seconds to wait for the gate; default 300. |
| `SONAR_PULL_REQUEST_KEY`, `SONAR_PULL_REQUEST_BRANCH`, `SONAR_PULL_REQUEST_BASE` | Set all three for PR analysis. |
| `SONAR_BRANCH_NAME` | Branch analysis instead of PR analysis; never combine contexts. |
| `COVERAGE_MINIMUM` | Shared local and new-code threshold; default 80. Change only for an explicit repository/task rule. |

Provide source/test roots and exclusions through the repository's `sonar-project.properties` or established scanner configuration. Install a scanner version that supports `SONAR_TOKEN`. The helper passes the selected LCOV paths using `sonar.javascript.lcov.reportPaths`, runs with `sonar.qualitygate.wait=true`, then queries the completed task's analysis ID. It requires the Quality Gate to include `new_coverage` and `new_bugs` and checks their actual values independently of the gate's thresholds. Gates using different metrics need a deliberate policy/tool update; they are not silently accepted.

Set `SONAR_REQUIRED=true` in CI jobs using this helper when Sonar is mandatory. No credentials means “Sonar not run,” never “gate passed.” Avoid scanner debug/verbose modes that could log secrets. Remote API redirects are rejected to avoid forwarding authentication to another destination.

## Authoritative references

- [Angular test command](https://angular.dev/cli/test) and [coverage configuration](https://angular.dev/guide/testing/code-coverage): consult the installed version's options.
- [Nx run tasks](https://nx.dev/docs/features/run-tasks) and [skip caching](https://nx.dev/docs/kb/skipping-cache).
- [SonarQube JavaScript/TypeScript coverage](https://docs.sonarsource.com/sonarqube-server/2025.5/analyzing-source-code/test-coverage/javascript-typescript-test-coverage) and [SonarScanner CLI](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/sonarscanner).
