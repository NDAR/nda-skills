---
name: java-spring-harness
description: Use when creating, changing, reviewing, testing, or completing any Java 25 and Spring Boot microservice change.
---

# Java Spring Harness

Coordinate the shared Java/Spring guides and computational checks. Keep repository instructions authoritative for service-specific exceptions; do not duplicate them in local `AGENTS.md` files.

## Required Workflow

1. Begin by explicitly invoking `java-spring-coding-standards`; report that exact skill name before editing Java or Spring Boot production or test code. Resolve task, repository, tool, local-pattern, and shared-standard precedence.
2. **REQUIRED SUB-SKILL:** Use `pair-programming-tdd` before implementing any Java or Spring Boot production or test-code change. Complete one story slice, report its TDD evidence, and wait for human approval before starting another slice.
3. **REQUIRED SUB-SKILL:** Use the applicable Superpowers workflow:
   - `superpowers:test-driven-development` before implementing a feature or bug fix.
   - `superpowers:systematic-debugging` before changing code to address a failure or unexpected behavior.
   - `superpowers:requesting-code-review` after a material implementation change.
4. Run the repository's fast, relevant checks while iterating. Follow service-specific commands where supplied.
5. **REQUIRED SUB-SKILL:** Stage the change (`git add -A`) and use `secrets-credential-scanning` with `SECRETS_SCAN_STAGED=true` before invoking `java-spring-verification`. A blocking, non-allowlisted finding must be resolved — credential rotation or a reviewed `.gitleaks.toml` entry — before continuing.
6. Before reporting completion, explicitly invoke `java-spring-verification`, then run its verification script from the target service root.
7. Report only fresh evidence: commands run, Maven result, JaCoCo coverage, SonarQube Quality Gate/new-code coverage/new-bug results when configured, and every unavailable or failing required check.

## Enforcement Boundary

This skill coordinates agent behavior. Maven configuration, SonarQube Quality Gates, CI, and repository hooks enforce policy only when the target repository configures and runs them. Do not claim that a skill alone guarantees a check ran.

Set `SONAR_REQUIRED=true` in CI when the CI job invokes the verification script and SonarQube analysis is mandatory. Local work without SonarQube credentials may report the check as pending CI, but must not claim full SonarQube verification.
