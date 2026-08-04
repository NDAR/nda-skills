---
name: java-spring-coding-standards
description: Use when creating, changing, reviewing, or testing Java 25 and Spring Boot code where shared standards may be superseded by target-repository conventions.
---

# Java Spring Coding Standards

Use the target repository's established rules first. This skill supplies a shared baseline only where those rules are absent.

## Resolve Conventions

Before editing, inspect the target repository's instructions, build and quality configuration, and nearby production and test code. Apply this precedence order:

```text
direct task requirements
> repository instructions and documented standards
> repository quality tooling and configuration
> adjacent production and test patterns
> shared Java/Spring baseline
```

An explicit target-repository rule overrides this baseline. State the override and how it changed the work in the final report.

## Shared Java/Spring Baseline

- Use clear, domain-oriented names; keep packages coherent with the repository's existing feature or layer layout.
- Prefer constructor injection; do not add field injection.
- Bind external configuration with `@ConfigurationProperties`, validate it with Bean Validation, and fail early for invalid required configuration.
- Validate untrusted input at API, messaging, or persistence boundaries; keep internal assumptions explicit.
- Map expected failures to stable, appropriate error responses without exposing implementation or sensitive details.
- Emit structured, useful logs with correlation/context where available; never log credentials, tokens, secrets, or unnecessary personal data.
- Define transaction boundaries around the smallest business operation that needs atomicity; do not span remote calls unnecessarily.
- Preserve documented API contracts and backwards compatibility unless the task explicitly authorizes a breaking change.
- Add or update tests that match the repository's test framework, style, fixtures, and level of isolation; cover the changed behavior and relevant failure path.

## Verify and Report

Run the repository's applicable quality checks. Report what ran and its result. If a check is unavailable, blocked, or fails, say so plainly with the reason and any remaining risk; do not claim verification that did not occur.
