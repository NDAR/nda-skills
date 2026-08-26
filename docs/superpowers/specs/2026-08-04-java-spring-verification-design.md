# Java Spring Verification Skill Design

## Goal

Provide a reusable end-of-change verification workflow for Java 25/Spring Boot services: run `mvn clean verify`, require at least 80% line coverage from JaCoCo, and, when configured, make SonarQube analysis fail on a non-OK Quality Gate, less than 80% new-code coverage, or any new bugs.

## Design

Create `skills/java-springboot/java-spring-verification/` with a concise `SKILL.md`, Codex UI metadata, and `scripts/verify-java-service.sh`.

The script runs from the target Maven repository, prefers an executable `./mvnw`, otherwise uses `mvn`, and always invokes `clean verify`. It reads a JaCoCo XML report and fails below 80% line coverage. SonarQube runs only when all connection values are provided: `SONAR_HOST_URL`, `SONAR_TOKEN`, and `SONAR_PROJECT_KEY`; `SONAR_REQUIRED=true` turns missing configuration into a failure. The scanner waits for the Quality Gate, then queries the project measures for `new_coverage` and `new_bugs` using the bearer token.

The skill requires agents to run the script only after code and tests are complete, report exact commands and results, and never claim compliance if the Maven, coverage, or required SonarQube check is unavailable or fails. It also directs users to configure their SonarQube Quality Gate for `new_coverage >= 80` and `new_bugs = 0`; the script verifies these values independently.

## Scope limits

No SonarQube host, token, project key, branch name, or pull-request identifier is committed. Repository-specific Sonar scanner properties and CI pull-request analysis settings remain authoritative.
