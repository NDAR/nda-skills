---
name: java-spring-verification
description: Use when completing or reviewing Java 25/Spring Boot changes that must pass Maven tests, satisfy at least 80% coverage, or meet SonarQube Quality Gate and new-bug requirements.
---

# Java Spring Verification

Run deterministic checks before reporting a Java service change as complete. Repository instructions and CI configuration override this skill, except where the task explicitly requires stricter checks.

## End-of-Change Workflow

1. Inspect the target repository for its Maven wrapper, JaCoCo configuration, Sonar scanner settings, and CI-provided SonarQube variables.
2. After code and tests are complete, run this bundled script from the target repository root:

   ```bash
   /path/to/java-spring-verification/scripts/verify-java-service.sh
   ```

   It always runs `./mvnw clean verify` when the wrapper is executable, otherwise `mvn clean verify`, then requires at least 80% JaCoCo line coverage.
3. When `SONAR_HOST_URL`, `SONAR_TOKEN`, and `SONAR_PROJECT_KEY` are available, the script runs SonarScanner for Maven, waits for the Quality Gate, and requires new-code coverage of at least 80% and zero `new_bugs`. Set `SONAR_REQUIRED=true` when SonarQube must not be skipped.
4. For pull-request or branch analysis, set `SONAR_PULL_REQUEST_KEY`, `SONAR_PULL_REQUEST_BRANCH`, and `SONAR_PULL_REQUEST_BASE`, or set `SONAR_BRANCH_NAME`.
5. Report the command, Maven result, JaCoCo percentage, SonarQube Quality Gate result, new-code coverage, and new-bug count. If any required check is unavailable or fails, state that plainly; do not claim completion.

## SonarQube Prerequisites

Require the target project’s Quality Gate to include `new_coverage >= 80` and `new_bugs = 0`. Keep `SONAR_TOKEN` only in an environment variable or secret store; never put it in commands, source, reports, or commits.
