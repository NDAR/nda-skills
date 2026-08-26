# Java Spring Verification Implementation Plan

**Goal:** Add a reusable Maven/SonarQube verification skill and script.

**Architecture:** Keep deterministic checks in a shell script and agent behavior in a short skill. Use JaCoCo XML for overall line coverage and SonarQube measures for changed-code coverage and bugs.

### Task 1: Add a failing shell regression test

- Create `skills/java-springboot/java-spring-verification/tests/verify-java-service-test.sh`.
- Test a temporary Maven fixture with a fake Maven wrapper, an 80% JaCoCo XML report, and no Sonar environment. Assert the verifier invokes `clean verify` and succeeds.
- Run the test before adding the verifier and confirm it fails because the verifier script is absent.

### Task 2: Add the verification script and skill

- Initialize `skills/java-springboot/java-spring-verification/` with UI metadata.
- Create `scripts/verify-java-service.sh` that runs Maven verification, parses JaCoCo line coverage, and conditionally runs SonarQube with a waiting Quality Gate and measure checks.
- Create `SKILL.md` directing agents to use the script after implementation, require exact evidence, and respect repository overrides.
- Re-run the shell test and validate the skill structure.

### Task 3: Publish and verify

- Bump `.codex-plugin/plugin.json` from `0.5.0` to `0.6.0`.
- Run the shell regression test, skill validator, JSON validation, and `git diff --check`.
