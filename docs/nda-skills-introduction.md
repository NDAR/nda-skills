---
marp: true
theme: default
paginate: true
footer: "nda-skills · shared context and quality controls for coding agents"
style: |
  section {
    font-size: 28px;
    padding: 58px 72px;
    color: #172033;
  }
  h1, h2, h3 {
    color: #003b70;
  }
  h1 {
    font-size: 1.7em;
  }
  h2 {
    font-size: 1.28em;
  }
  strong, em {
    color: #007f86;
  }
  code {
    font-size: 0.72em;
  }
  pre {
    font-size: 0.62em;
  }
  table {
    font-size: 0.78em;
  }
  blockquote {
    border-left-color: #00a6a6;
    color: #334155;
  }
  section.image-slide {
    text-align: center;
  }
  section.image-slide h1 {
    text-align: left;
  }
  section.image-slide p {
    margin: 0.25em 0;
  }
---

<!-- _paginate: skip -->
<!-- _class: lead -->

# nda-skills

## From a chat prompt to a shared coding-agent harness

**A practical introduction for NDA software developers**

<!--
Open with the key idea: the model does not see our organization, codebase,
standards, or delivery expectations unless we make those things available.
nda-skills makes selected parts of that context reusable.
-->

---

# Sound familiar?

- An agent commits code that doesn't match our Java conventions—because it never saw them.
- A change almost merges with a leaked API key, because nothing scanned the diff.
- The agent keeps making the same style mistake that you corrected every time, because no memory was kept forward.

**None of this is a smarter-model problem. It's a context problem: the agent never had what it needed, when it needed it.**

<!--
Open with recognition, not theory—ask the room "has this happened to you?"
before moving into why it happens. These are the exact failure modes
nda-skills targets: conventions (java-spring-coding-standards), secrets
(secrets-credential-scanning), and repeated review friction (the "team
improves a skill" step in the developer loop, later in this deck).
-->

---

# Outline

1. Why context management is the real problem
2. From prompts to harnesses
3. What nda-skills provides today
4. How the workflows support quality
5. How to start using and improving them

---

# The evolution: prompt → context → harness

| Stage               | What we give the agent                                | Limitation                                  |
| ------------------- | ----------------------------------------------------- | ------------------------------------------- |
| **Chat prompt**     | A request and a few constraints                       | Important details disappear or are repeated |
| **Managed context** | Repository docs, conventions, tools, and examples     | Context is still easy to omit or contradict |
| **CLI harness**     | Reusable guidance plus checks in the development loop | Requires deliberate team maintenance        |

> At its core, agent-assisted development is about managing the **context and prompt** sent to the model.

<!--
Do not imply that chat is bad. A prompt is still useful; the issue is trying
to carry durable team knowledge and quality controls entirely in each chat.
-->

---

# Context is more than the prompt box

When a coding agent works in a repository, its effective context includes:

- the task and acceptance criteria
- repository instructions and architecture
- language and framework conventions
- available tools, tests, and quality gates
- feedback from commands it has just run

**Good context is relevant, current, discoverable, and actionable.**

<!--
Tie this to daily experience: humans gain this context gradually. Agents need
the important pieces surfaced explicitly and at the right time.
-->

---

<!-- _class: image-slide -->

# A harness makes the context operational

![w:760](assets/harness-overview.png)

**Guides steer the first attempt; sensors give the agent a chance to self-correct.**

<!--
Use the visual to describe the loop from human steering to guides and sensors.
Call out that the first visual category (guides) is feedforward, while the
second (sensors) creates feedback after the agent has acted.
-->

---

# Two vocabularies, one distinction

*Different axis from guides/sensors: that was about* when *a control fires (before vs. after the agent acts). This is about* how *it decides (fixed rule vs. judgment). A hook is typically a sensor; a skill can act as either.*

| Control type | Mechanism | Strength | Current NDA example |
| --- | --- | --- | --- |
| **Computational** | **Hooks** — a deterministic command at a lifecycle event | Fast, repeatable, no judgment required | Trusted `PreToolUse` gate before Codex runs a `git commit` or `git push` command |
| **Inferential** | **Skills** — focused context that coordinates a workflow | Semantic judgment, richer interpretation | Guidance for when and how to scan and remediate credentials |

Use fast computational controls (hooks) during the coding loop. Use inferential controls (skills) where the question needs judgment—and treat their output as input to review, not proof.

`secrets-credential-scanning` is deliberately **both**: the skill supplies the workflow and remediation context; the hook is its computational backstop. It fails **closed**—if `gitleaks` isn't installed, the hook blocks the commit rather than skipping the scan.

<!--
Computational controls and hooks are the same idea; inferential controls and
skills are the same idea. The important contrast is not "old tools versus
AI"—both are harness controls. Hook/computational feedback is cheap enough to
shift left; skill/inferential feedback helps with meaning and trade-offs, but
is slower and probabilistic. Do not present hooks as a replacement for
skills, or vice versa.
-->

---

<!-- _class: image-slide -->

# Where nda-skills sits

![w:840](assets/harness-bounded-contexts.png)

**Codex provides the inner harness. We add an outer harness tailored to NDA's development environment.**

<!--
This zooms into the "CLI harness" row of the prompt→context→harness table
from earlier: Codex is the inner harness, and this diagram shows the outer,
team-maintained layer we add on top of it. The article labels the outer layer
"user harness." In this talk, that is the team-level outer harness we create
for NDA. Emphasize that nda-skills augments Codex; it does not replace the
agent's own system instructions, tooling, retrieval, or orchestration.
-->

---

# obra/superpowers: a process framework

[`obra/superpowers`](https://github.com/obra/superpowers) is a composable-skill framework and development methodology for coding agents.

It provides general, reusable process skills such as:

- **Shape the work:** brainstorming, design, planning, and worktree setup
- **Build safely:** test-driven development, systematic debugging, and task execution
- **Close with evidence:** code review, verification, and branch completion

Its skills make disciplined practices available at the point a coding task needs them.

---

# nda-skills: the NDA specialization layer

This is the outer harness from the previous diagram, made concrete. `nda-skills` builds on that pattern with the context that generic process skills cannot know:

| Today | Growing from development evidence |
| --- | --- |
| Common skills: pair-programming TDD, CodeCommit PR work, credential scanning, and a pre-Git credential hook | **Angular** and **Python** skills *(not yet shipped)* |
| Language-specific skills: **Java/Spring Boot** standards, harness, and verification | Additional **sensors** and feedback controls as we learn where agents need more guidance |

```text
Task → Codex matches relevant installed skills
     → Superpowers process guidance + nda-skills specialization
     → focused instructions enter the agent's working context
```

**The agent uses installed matching skills during a task; it does not fetch their instructions from the network at runtime.**

<!--
Make the boundary clear: Java/Spring Boot is the current language-specific
coverage. The roadmap is intentionally evidence-driven: add Angular, Python,
and further sensors as team experience reveals repeatable needs.
-->

---

# nda-skills is a team-maintained outer harness

**One repository, many consumers.** `nda-skills` is a Codex plugin marketplace containing shared skill instructions.

- Skills are selected from their descriptions when the task matches.
- They add focused context at the time it is useful—rather than putting every rule in every prompt.
- **Installing more skills doesn't bloat every session.** A skill's full instructions only enter context when its description matches the task—unmatched skills cost nothing.
- They coordinate work with existing engineering controls; they do not replace them.

**Current focus:** shared workflow and security controls, plus Java/Spring guidance and verification.

---

# Inside the nda-skills repository

```text
hooks/
├── hooks.json           Codex lifecycle-event registration
└── scripts/             Deterministic hook commands
skills/
├── common/             Cross-stack workflows and credential scanning
└── java-springboot/    Current Java and Spring Boot guidance
```

**Roadmap (not in the repo yet):** Angular/Electron and Python skill folders, added when that work starts.

- A stack folder groups related skills; each skill is a folder containing a `SKILL.md` with a trigger description and instructions.
- `hooks/` contains deterministic lifecycle controls; it is separate from the context and workflow instructions under `skills/`.
- `common/` holds reusable workflows. Stack folders hold conventions, harnesses, and verification relevant to that ecosystem.
- Grouping keeps the repository maintainable; **the skill description determines when Codex applies it.**

<!--
Use the tree as a map: common is cross-stack; Java/Spring Boot exists today.
The tree shows exactly what `ls skills/` returns right now — Angular/
Electron and Python are called out separately as roadmap so nobody walks
away thinking those folders exist yet. The folders organize the skills,
while each skill's description controls its activation.
-->

---

# Getting started

**Four steps, about five minutes.**

0. **Check prerequisites** — working HTTPS git auth, and `gitleaks` on your PATH (`brew install gitleaks`) for the credential hook:

   ```zsh
   git ls-remote https://github.com/NDAR/nda-skills.git
   ```

   Lists refs without prompting? You're set. Prompts or fails? Fix HTTPS git auth first (PAT in your credential helper, or `gh` configured).

1. **Install:**

   ```zsh
   codex plugin marketplace add https://github.com/NDAR/nda-skills.git --ref main
   codex plugin add nda-skills@nda-skills
   ```

2. **Restart Codex, then verify:**

   ```zsh
   codex plugin list
   ```

   Look for `nda-skills@nda-skills` — `installed, enabled`.

3. **Trust the hook:** open `/hooks`, review the `nda-skills` definition, and trust it. Skills work without this step; the commit/push credential gate does not.

**Later:** `codex plugin marketplace upgrade` pulls published improvements — no reinstall needed.

<!--
This is the slide developers will screenshot — say the commands out loud and
pause here, since this is the point where people actually pull out a laptop.
The prerequisite check catches the most common install failure (broken HTTPS
git auth) before it derails a live follow-along. The marketplace lets the
team ship refinements once and lets developers pull them with a single
upgrade command; this is the distribution mechanism, not a replacement for
each repository's own rules.
-->

---

# Java/Spring delivery workflow (1/2): start → build → iterate

| Stage | Skills and controls that enter here |
| --- | --- |
| **Start the change** | `java-spring-harness` coordinates; it invokes `java-spring-coding-standards` first. Repository rules remain authoritative. |
| **Build one small behavior** | `pair-programming-tdd` drives RED → GREEN → refactor. Applicable Superpowers skills support TDD, debugging, and code review. |
| **Iterate with feedback** | Run the repository's fast, relevant checks while the change is small. |

**The harness supplies the right context at each stage—not every instruction at once.**

<!--
java-spring-harness is the coordinator for the whole workflow (both halves of
this table). It requires the coding-standards skill first, then
pair-programming TDD during implementation, running fast repository checks
while the change is still small enough to fix cheaply.
-->

---

# Java/Spring delivery workflow (2/2): prepare → verify

| Stage | Skills and controls that enter here |
| --- | --- |
| **Prepare completion** | Stage changes with `git add -A`; `secrets-credential-scanning` directs a staged gitleaks scan. A trusted `PreToolUse` hook independently blocks Codex-issued `git commit` or `git push` unless its scan passes. |
| **Verify and report** | `java-spring-verification`: Maven, at least 80% JaCoCo line coverage, and optional SonarQube Quality Gate checks. |

**Feedback arrives before the change ships—not after review finds it.**

<!--
A staged secrets scan runs before completion is reported. The trusted hook
adds an independent, final computational gate before Codex commits or
pushes—it does not replace CI or PR-range scanning, and it fails closed if
gitleaks isn't installed locally. Verification requires fresh Maven/JaCoCo
evidence (and Sonar, where configured) before the change is called done.
-->

---

# If the change becomes a CodeCommit PR *(only if your team uses CodeCommit)*

Two skills, sequenced around the PR's actual lifecycle:

**`codecommit-pr-create`** opens the PR once implementation is verified — resolves the Jira ticket and local branch, derives the destination branch and title from the Jira key, scans the `destination→source` range with `secrets-credential-scanning`, then creates the PR. Confirms with you before any mutation.

**`codecommit-pr-merge`** guides the merge later, after review:

1. **Find and inspect the right PR** — confirm repository, source/destination branches, commits, and approvals.
2. **Review the diff.**
3. **Re-scan the PR range** — `secrets-credential-scanning` checks `destinationCommit..sourceCommit` again, independently of the create-time scan; a non-allowlisted finding blocks the merge.
4. **Verify merge readiness** — run the project's verification command and confirm approvals are satisfied.
5. **Merge safely, then clean up** — squash merge using the current source commit; delete **only** the verified source branch.

**The destination branch is never deleted.**

<!--
Two separate skills: codecommit-pr-create opens the PR (often right after
java-spring-verification passes), codecommit-pr-merge closes it out later,
typically in a separate request or session. Both are optional — only
relevant for teams using AWS CodeCommit. Emphasize there are two
independent secrets scans (create-time and merge-time), and branch deletion
happens only after a verified merge.
-->

[Maintainability sensors for coding agents](https://martinfowler.com/articles/sensors-for-coding-agents.html)

---

# See it work

**Demo (~60–90 seconds): a fake secret gets caught before it ships.**

```bash
echo 'aws_key = "AKIAIOSFODNN7EXAMPLE"' >> demo.txt
git add demo.txt
# Ask Codex to commit — the PreToolUse hook scans staged changes first
```

Codex's `git commit` is denied, with a redacted reason, before the secret ever reaches git history. Clean up `demo.txt` afterward.

**Backup demo (no live Codex session needed):** run the scanner directly —

```bash
skills/common/secrets-credential-scanning/scripts/scan-secrets.sh
```

**If live demo isn't possible:** narrate it from this slide — stage a fake key, the hook masks and blocks it, nothing sensitive reaches chat history or git log.

<!--
This demo needs no Java service and takes under a minute — a safe default
for a mixed-stack room. If a Java service is on hand and coverage is more
relevant to this audience, swap in: run java-spring-verification against a
change below 80% coverage and show the agent respond to the failure. Either
way, the point is "the loop is real," not a full walkthrough of either
skill. Remove demo.txt and unstage before moving on so the repo stays clean.
-->

---

# The developer loop we are building

```text
Developer goal
    ↓
Relevant skills and trusted hooks supply focused context and guardrails
    ↓
Agent changes code in a small, inspectable slice
    ↓
Tests / static analysis / credential scanning / coverage provide feedback
    ↓
Agent corrects; developer reviews the important judgment calls
    ↓
Team improves a skill, hook, or repository control when a pattern repeats
```

This is **harness engineering as an ongoing practice**, not a one-time prompt template.

---

# Worked example: "complete this Jira story"

For a Java/Spring service, one request threads through most of the repository:

1. **`java-spring-harness`** matches the task and coordinates everything below.
2. → **`java-spring-coding-standards`**, invoked first, before any code changes.
3. → **`pair-programming-tdd`**, one slice at a time — RED → GREEN → refactor, human approval between slices. Applicable Superpowers skills (TDD, debugging, code review) apply inside each slice.
4. → fast-check script runs while iterating (format, architecture sensor, touched tests).
5. → **`secrets-credential-scanning`** (staged scan) before verification.
6. → **`java-spring-verification`** — Maven, ≥80% JaCoCo, Sonar Quality Gate if configured.
7. → **`codecommit-pr-create`** — matches "PR for a Jira ticket," opens the PR, with its own destination→source secrets scan.
8. *(Later, separate request)* → **`codecommit-pr-merge`** — re-scans the PR range independently, then merges.

**Throughout:** the `PreToolUse` hook intercepts every Codex-issued `git commit`/`git push`, regardless of which skill is driving at the time — it isn't matched by description like a skill is.

**A different stack today means a much shorter list:** only `pair-programming-tdd`, `secrets-credential-scanning`, and the hook apply outside Java/Spring — no coding-standards, harness, or verification skill exists yet for that repository.

<!--
This is the abstract loop from the previous slide, made concrete with real
skill names and ordering — use it to ground the whole talk in one example
the room can follow start to finish. The stack caveat matters: don't let the
room walk away thinking every skill named here fires for every language.
-->

---

# When the harness gets in your way

Guardrails will occasionally be wrong. Know the escape hatch before you need it.

- **Hook blocks a legitimate commit (false-positive secret):** confirm with a human it isn't real, then add a narrowly-scoped entry to a repo-root `.gitleaks.toml`—exact path or exact string, never a blanket rule—and get it reviewed like any other code change.
- **A skill's guidance doesn't fit this repository:** repository instructions and CI configuration are authoritative over a skill's default guidance, except where the task explicitly needs stricter checks.
- **SonarQube isn't configured for this service:** verification still runs Maven and JaCoCo; Sonar checks are skipped rather than blocking, unless `SONAR_REQUIRED=true` is set.
- **A skill fires when it shouldn't, or never fires when it should:** that's feedback for us, not a bug to route around—see the closing section for how to change it.

**Nothing here is unappealable. The point is judgment stays with the reviewer, not the tool.**

<!--
This slide exists because the first question from an experienced developer
in the room will be "what happens when this is wrong." Have the
.gitleaks.toml example from the secrets-credential-scanning skill ready if
asked for more detail.
-->

---

# What nda-skills does _not_ automate away

- Clear product intent and acceptance criteria
- Trade-offs between simplicity, delivery speed, and technical debt
- Security, privacy, and operational accountability
- Human code review and ownership

> A good harness directs human attention to the decisions that matter most; it does not eliminate it.

---

# Sources and further reading

- Birgitta Böckeler, [Harness engineering for coding agent users](https://martinfowler.com/articles/harness-engineering.html), Martin Fowler, 2 April 2026.
- Birgitta Böckeler, [Maintainability sensors for coding agents](https://martinfowler.com/articles/sensors-for-coding-agents.html), Martin Fowler, 27 May 2026.
- [`obra/superpowers`](https://github.com/obra/superpowers) — the composable skill framework and development methodology that nda-skills builds upon.
- [Codex hooks documentation](https://developers.openai.com/codex/hooks) — lifecycle events, trust review, and plugin hook configuration.
- [gitleaks](https://github.com/gitleaks/gitleaks) — credential scanner used by the `secrets-credential-scanning` skill.
- Embedded diagrams: *Harness overview* and *Harness bounded contexts*, reproduced from the harness-engineering article above; attribution is retained in each image.
- [Marpit directives documentation](https://marpit.marp.app/directives) — YAML front matter, pagination, footers, and CSS styling.
- This repository: [`README.md`](../README.md) and the current [`skills/`](../skills/) directory.

<!--
The deck paraphrases the Fowler articles. Their central ideas used here are
guides/sensors, computational/inferential controls, and shifting fast
feedback left. The repo files are the source of truth for nda-skills scope
and commands.
-->

---

# Start small; improve from evidence

1. Install the plugin and try a relevant workflow on a real task.
2. Notice repeated agent or review friction.
3. Decide whether the missing control is a **guide**, a **sensor**, or both.
4. Improve the skill, hook, or repository control; publish the change through the marketplace.
5. Upgrade and share what changed.

**A useful skill turns one team's learned context into a reusable advantage for everyone.**

Bring back the rough edges—**where did the agent lack context? what feedback arrived too late?**—and open a PR into `main` on [`NDAR/nda-skills`](https://github.com/NDAR/nda-skills). Merge = live for the team on the next `marketplace upgrade`.
