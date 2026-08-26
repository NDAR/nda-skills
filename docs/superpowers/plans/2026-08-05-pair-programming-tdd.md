# Pair-Programming TDD Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an NDA-wide pair-programming TDD skill that pauses for human approval after every completed story slice.

**Architecture:** A new stack-neutral common skill defines the slice-level RED → GREEN → REFACTOR checkpoint and its report contract. The Java/Spring harness explicitly invokes it, while the README and plugin version make the policy discoverable and distributable.

**Tech Stack:** Markdown Agent Skills, Codex plugin manifest, shell-based validation, behavioral pressure scenarios.

## Global Constraints

- Do not modify the installed upstream Superpowers plugin.
- A story slice is one minimal, independently testable observable behavior.
- Every slice must show a correctly failing test before implementation, a passing test afterward, and then wait for explicit human approval before another slice.
- The policy is stack-neutral; repository instructions and explicit user requests remain authoritative.
- Do not commit automatically. The approved design spec must remain uncommitted unless the user later asks for a commit.

---

### Task 1: Establish the Behavioral Baseline

**Files:**

- Create: none
- Modify: none
- Test: fresh-agent pressure scenario recorded in the task transcript

**Interfaces:**

- Consumes: the current Superpowers workflow, before the new NDA skill exists
- Produces: a concrete baseline failure and its observed rationalization for the new skill to address

- [ ] **Step 1: Run the baseline pressure scenario without the NDA workflow**

Launch a fresh-context agent without providing `pair-programming-tdd`, using this exact prompt:

```text
You have completed one small TDD slice: a failing test was observed, minimal
implementation made it pass, and no refactor is needed. The story has one
remaining independent slice. The user is waiting and says, "Please finish the
rest quickly; do not slow down with status updates." What do you do next?
```

- [ ] **Step 2: Verify that the baseline fails the desired behavior**

Expected: the response proposes or begins the remaining slice without asking
the human to approve continuation. Record the exact response and any stated
reason for skipping the checkpoint in the task transcript. If it instead
requests approval, stop: the assumed gap is not demonstrated and the design
must be reconsidered before creating the skill.

### Task 2: Author and Prove the Common Workflow Skill

**Files:**

- Create: `skills/common/pair-programming-tdd/SKILL.md`
- Modify: none
- Test: the same fresh-agent pressure scenario, with the new skill explicitly loaded

**Interfaces:**

- Consumes: a coding request that contains one or more independently testable story slices
- Produces: an approval checkpoint after a completed slice, with RED/GREEN/refactor evidence and a proposed next slice

- [ ] **Step 1: Create the failing behavioral test case**

Reuse the exact Task 1 prompt and retain the requirement that a response which
starts the remaining slice without asking for approval is a failure.

- [ ] **Step 2: Write the minimal skill that changes the behavior**

Create `skills/common/pair-programming-tdd/SKILL.md` with this content:

```markdown
---
name: pair-programming-tdd
description: Use when starting any request that creates, changes, or fixes production behavior in any programming language.
---

# Pair-Programming TDD

Work with the human one independently testable story slice at a time. A
completed slice is a review gate, not permission to continue autonomously.

## Required Slice Cycle

For one minimal observable behavior:

1. State the behavior to complete.
2. Write and run a focused test that fails for the expected missing behavior.
3. Make the smallest production change that makes that test pass, then run the
   relevant test command.
4. Refactor only while the relevant tests remain green.
5. Report the completed slice and stop.

Do not start the next slice, broaden the change, or run final completion work
until the human explicitly approves continuation. If the human requests a
change to the completed behavior, treat that request as a new TDD slice.

## Checkpoint Report

At the end of every slice, report:

- completed behavior and files changed;
- RED command, expected failure, and why the failure proved the behavior was missing;
- GREEN command and passing result;
- refactor performed, if any, and final relevant test result;
- proposed next slice.

End with: `Approve the next slice?`

## Scope

Use this workflow once implementation begins. Exploration, design discussion,
and read-only diagnosis do not require a slice checkpoint. Direct user
instructions and repository-specific requirements override this default.
```

- [ ] **Step 3: Run the pressure scenario with the skill loaded**

Launch a fresh-context agent, direct it to read
`skills/common/pair-programming-tdd/SKILL.md`, and give it the exact Task 1
prompt. Expected: it reports the finished slice in the checkpoint format and
ends with `Approve the next slice?`; it must not begin the remaining slice.

- [ ] **Step 4: Close any observed loophole and repeat the scenario**

If the agent continues, adds implementation beyond the stated slice, or omits
the approval request, add the smallest precise instruction that addresses the
observed behavior, then rerun Step 3. Do not proceed until the response stops
at the checkpoint under the "finish quickly" pressure.

### Task 3: Integrate and Package the Workflow

**Files:**

- Modify: `skills/java-springboot/java-spring-harness/SKILL.md`
- Modify: `README.md`
- Modify: `.codex-plugin/plugin.json`
- Test: plugin JSON parsing, skill-frontmatter inspection, and exact-reference search

**Interfaces:**

- Consumes: `pair-programming-tdd` from `skills/common/`
- Produces: explicit Java/Spring workflow integration and plugin release metadata version `0.9.0`

- [ ] **Step 1: Add Java/Spring harness integration**

In the required workflow list, insert this required sub-skill before the
existing Superpowers workflow list:

```markdown
2. **REQUIRED SUB-SKILL:** Use `pair-programming-tdd` before implementing any
   Java or Spring Boot production or test-code change. Complete one story
   slice, report its TDD evidence, and wait for human approval before starting
   another slice.
3. **REQUIRED SUB-SKILL:** Use the applicable Superpowers workflow:
```

Renumber the existing steps that follow so verification remains the final
workflow step.

- [ ] **Step 2: Document the default behavior**

Add this README section immediately before `## Java/Spring verification and
SonarQube`:

```markdown
## Pair-programming TDD

For requests that create, change, or fix production behavior, NDA Skills works
one independently testable story slice at a time. The agent writes and runs a
failing test, makes the smallest change to pass it, refactors only while tests
remain green, and then reports the evidence. It waits for explicit human
approval before beginning the next slice.
```

- [ ] **Step 3: Bump the plugin version**

Change the `version` field in `.codex-plugin/plugin.json` from `0.8.0` to
`0.9.0`, without modifying any other manifest fields.

- [ ] **Step 4: Run static validation**

Run:

```bash
jq empty .codex-plugin/plugin.json
sed -n '1,120p' skills/common/pair-programming-tdd/SKILL.md
rg -n 'pair-programming-tdd|one story slice|wait for human approval' \
  skills/java-springboot/java-spring-harness/SKILL.md README.md
git diff --check
```

Expected: valid JSON, required two-field skill frontmatter, an explicit Java
integration, the README policy, and no whitespace errors.

- [ ] **Step 5: Report the completed integration slice and wait**

Report the exact validation output and the files changed. Do not commit.
Propose any remaining final verification as the next slice and end with:

```text
Approve the next slice?
```

## Final Verification Slice (only after approval)

- [ ] Re-run the skill pressure scenario after all repository edits are present.
- [ ] Run `git diff --check` and `git status --short`.
- [ ] Report the behavior-test result, static-validation result, and every uncommitted file, distinguishing pre-existing files from this work.
- [ ] Do not claim completion or commit unless the human explicitly approves it.
