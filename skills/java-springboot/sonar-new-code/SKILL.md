---
name: sonar-new-code
description: Use when running or reporting SonarQube new-code analysis from the command line for a Java/Spring service, especially for a branch or pull request before review or merge.
---

# Sonar New-Code Sensor

Run the command-line complement to VS Code's SonarQube Focus on New Code. It
performs server-side branch or pull-request analysis, waits for the Quality
Gate, and emits a concise new-code report.

## Preconditions

Run after the relevant tests and coverage report exist. For a complete Java
service verification, use `java-spring-verification`; this sensor is the
focused SonarQube signal, not a replacement for Maven or JaCoCo verification.

Set `SONAR_HOST_URL`, `SONAR_TOKEN`, and `SONAR_PROJECT_KEY` in the environment.
Never place a token in a command, source file, report, or commit.

Select exactly one analysis context:

- Pull request: set `SONAR_PULL_REQUEST_KEY`, `SONAR_PULL_REQUEST_BRANCH`, and
  `SONAR_PULL_REQUEST_BASE`.
- Branch: set `SONAR_BRANCH_NAME`.
- Local fallback: leave both unset only when the current Git branch is the
  intended, analyzed SonarQube branch.

## Run and Interpret

From the Maven project root, run:

```bash
/path/to/sonar-new-code/scripts/check-sonar-new-code.sh
```

Report the Quality Gate plus new-code coverage, bugs, vulnerabilities, code
smells, security hotspots, and duplicated-lines density. `N/A` means the
server did not return that metric; do not invent a value. Treat a non-OK
Quality Gate or a failed command as a failed sensor. The server Quality Gate
defines policy thresholds and remains authoritative.
