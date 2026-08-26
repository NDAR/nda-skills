# Java Spring Coding Standards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a distributable Java 25/Spring Boot coding-standards skill that applies shared defaults and honors repository-specific overrides.

**Architecture:** Add one concise, stack-scoped skill with Codex UI metadata. It resolves conventions using an explicit precedence order, then verifies changes with the target repository's own checks. Bump the plugin version so marketplace consumers receive the skill.

**Tech Stack:** Markdown Agent Skill, Codex plugin metadata, Python skill-authoring validators.

## Global Constraints

- Create the skill under `skills/java-springboot/`, not `skills/common/`.
- Keep the baseline generic: no service names, accounts, paths, credentials, or unverified organization-specific rules.
- Explicit repository rules override the shared baseline.
- Preserve the pre-existing unstaged `README.md` modification.
- Bump `.codex-plugin/plugin.json` from `0.4.0` to `0.5.0`.

---

### Task 1: Add the Java/Spring standards skill

**Files:**

- Create: `skills/java-springboot/java-spring-coding-standards/SKILL.md`
- Create: `skills/java-springboot/java-spring-coding-standards/agents/openai.yaml`

**Interfaces:**

- Consumes: Target repository instructions, build configuration, automated quality tools, and adjacent source/test patterns.
- Produces: A resolved convention set for code generation and an honest verification report.

- [ ] **Step 1: Initialize the skill structure and agent metadata**

Run:

```bash
python3 /Users/sarkard/.codex/skills/.system/skill-creator/scripts/init_skill.py java-spring-coding-standards --path skills/java-springboot --interface display_name='Java Spring Coding Standards' --interface short_description='Apply shared Java and Spring coding standards with repository overrides.' --interface default_prompt='Apply our Java and Spring coding standards to this change, honoring repository-specific overrides.'
```

- [ ] **Step 2: Write the skill instructions**

Replace the generated `SKILL.md` with a concise workflow that requires this precedence order:

```text
direct task requirements
> repository instructions and documented standards
> repository quality tooling and configuration
> adjacent production and test patterns
> shared Java/Spring baseline
```

Include a baseline covering names and package layout; Javadoc for classes, public methods, and private methods with significant non-obvious behavior; constructor injection; `@ConfigurationProperties` validation; boundary validation; error mapping; structured and non-sensitive logs; transaction boundaries; API compatibility; and repository-matching tests. Require the agent to disclose a repository override and to report unavailable or failed checks.

- [ ] **Step 3: Validate the skill structure**

Run:

```bash
python3 /Users/sarkard/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/java-springboot/java-spring-coding-standards
```

Expected: successful validation with a valid hyphen-case name, YAML frontmatter, and required description.

### Task 2: Publish the skill through the plugin manifest

**Files:**

- Modify: `.codex-plugin/plugin.json`

**Interfaces:**

- Consumes: plugin version `0.4.0`.
- Produces: plugin version `0.5.0` so marketplace upgrades surface the new skill.

- [ ] **Step 1: Update the manifest version**

Change the version field exactly:

```json
"version": "0.5.0"
```

- [ ] **Step 2: Validate JSON and final repository changes**

Run:

```bash
python3 -m json.tool .codex-plugin/plugin.json >/dev/null
git diff --check
git status --short
```

Expected: valid JSON, no whitespace errors, only the new skill, plugin manifest update, and already-existing README modification.

- [ ] **Step 3: Commit the implementation without staging README.md**

Run:

```bash
git add skills/java-springboot/java-spring-coding-standards .codex-plugin/plugin.json
git commit -m 'feat: add Java Spring coding standards skill'
```

Expected: the new skill and version bump are committed; `README.md` remains unstaged.
