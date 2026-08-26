# Java Spring Coding Standards Skill Design

## Goal

Provide a shared Java 25 and Spring Boot microservice coding standard that guides code generation and review, while allowing a target repository to override it deliberately.

## Placement and distribution

Create `skills/java-springboot/java-spring-coding-standards/` with a `SKILL.md` and `agents/openai.yaml`. Bump the plugin version so marketplace users receive the addition.

## Precedence model

Resolve conventions in this order:

1. Direct task requirements.
2. Repository instructions and documented standards.
3. Enforced repository tooling and configuration.
4. Established adjacent production and test patterns.
5. This skill's shared baseline.

Treat an explicit higher-precedence rule as an override. Do not invent a convention when evidence conflicts or is absent; state the ambiguity and ask or make the smallest compatible choice.

## Shared baseline

The skill will direct agents to use idiomatic Java 25 and Spring Boot service conventions: clear package and type names; Javadoc for classes, public methods, and private methods with significant non-obvious behavior; constructor injection; validated configuration properties; boundary validation; consistent exception-to-problem response handling; structured, non-sensitive logging; explicit transaction boundaries; stable API compatibility; and tests that match repository conventions.

The baseline is guidance, not a replacement for repository policy or automated enforcement.

## Workflow and verification

Before editing, inspect the target repository's instructions, Maven configuration, formatter and static-analysis configuration, and neighboring production/test code. Apply the resolved conventions consistently throughout the change. Run the formatter, static checks, and focused tests that the repository exposes. Never claim conformance when a relevant check was unavailable or failed; report the exact limitation instead.

## Out of scope

Do not embed organization-specific package names, credentials, service names, or undocumented architecture rules. Do not duplicate generic TDD, debugging, or PR workflows already provided by Superpowers and the existing CodeCommit skill.
