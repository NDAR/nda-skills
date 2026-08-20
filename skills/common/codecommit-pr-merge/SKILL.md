---
name: codecommit-pr-merge
description: Use when asked to review, verify, squash-merge, or clean up an AWS CodeCommit pull request, especially from a Jira ticket, across repositories; includes finding associated PRs, checking AWS profiles, producing merge commit messages, preserving the destination branch, and deleting only the merged source branch after approval.
---

# CodeCommit PR Merge

## Overview

Use this workflow for CodeCommit PR operations where correctness depends on identifying the right AWS profile, repository, source branch, destination branch, approval state, and post-merge cleanup. Treat branch deletion as a separate verified step after the merge succeeds.

## Operating Rules

- Never delete the destination branch.
- Never delete any branch until the PR is verified as merged.
- Never merge if approval rules are unsatisfied; report the blocker and pause.
- Never merge if `secrets-credential-scanning` reports a blocking, non-allowlisted finding for the PR's commit range.
- Always use the current PR source commit in `merge-pull-request-by-squash`.
- Always verify the exact source and destination before merge, and verify final state after branch deletion.
- Use `nih_mgmt` if the user explicitly says to use it; otherwise discover profiles with `aws configure list-profiles` and test repository access.
- When a command requires network access or remote state changes, request escalation according to the active environment policy.

## Find the PR

If starting from Jira:

1. Load the Jira ticket.
2. Check visible description/comments and Jira development fields for pull request counts.
3. If Jira does not expose the PR, inspect the local repo:
   - `git remote -v`
   - `git log --all --oneline --grep=<JIRA-KEY>`
   - `git branch -a --list '*<JIRA-KEY>*'`
   - `git ls-remote --heads origin`
4. Use AWS CodeCommit with the correct profile:
   - `aws codecommit get-repository --repository-name <repo> --profile <profile> --region <region>`
   - `aws codecommit list-pull-requests --repository-name <repo> --pull-request-status OPEN --profile <profile> --region <region>`
   - Include `CLOSED` PRs when the likely branch was already merged.
5. Fetch candidate PR details one at a time:
   - `aws codecommit get-pull-request --pull-request-id <id> --profile <profile> --region <region>`

Prefer a PR whose title, source branch, destination branch, or source commit matches the Jira ticket and local Git evidence.

## Review Changes

Use the PR's `destinationCommit` and `sourceCommit`:

```bash
git fetch origin <destination-branch> <source-branch>
git diff --stat <destinationCommit>..<sourceCommit>
git diff --name-status <destinationCommit>..<sourceCommit>
git log --oneline <destinationCommit>..<sourceCommit>
git diff --check <destinationCommit>..<sourceCommit>
```

Review changed files directly. For code-review requests, lead with findings ordered by severity. If no blocking issues are found, say so and include verification evidence.

**REQUIRED SUB-SKILL:** Use `secrets-credential-scanning` with `SECRETS_SCAN_BASE=<destinationCommit>` and `SECRETS_SCAN_HEAD=<sourceCommit>` before recommending merge. A blocking, non-allowlisted finding pauses the merge until the human resolves it.

Run the appropriate project verification command before recommending merge. Prefer the full test command when practical.

## Draft Squash Message

Use this structure:

```text
<JIRA-KEY> <imperative summary>

<What changed and why. Mention external service contracts, auth behavior, data changes, or user-visible effects.>

<Tests/build metadata/cleanup notes when relevant.>
```

Keep it accurate to the diff, not just the ticket title.

## Merge

Before merging, verify the PR:

```bash
aws codecommit get-pull-request \
  --pull-request-id <pr-id> \
  --profile <profile> \
  --region <region> \
  --query 'pullRequest.{id:pullRequestId,status:pullRequestStatus,source:pullRequestTargets[0].sourceReference,destination:pullRequestTargets[0].destinationReference,sourceCommit:pullRequestTargets[0].sourceCommit,destinationCommit:pullRequestTargets[0].destinationCommit,mergeBase:pullRequestTargets[0].mergeBase,isMerged:pullRequestTargets[0].mergeMetadata.isMerged,revisionId:revisionId}' \
  --output json
```

Confirm:

- `status` is `OPEN`
- `destination` is the branch the user intends, commonly `refs/heads/main`
- `source` is the branch the user intends to delete after merge
- `isMerged` is false
- the merge command uses the returned `sourceCommit`

Run:

```bash
aws codecommit merge-pull-request-by-squash \
  --pull-request-id <pr-id> \
  --repository-name <repo> \
  --source-commit-id <sourceCommit> \
  --profile <profile> \
  --region <region> \
  --commit-message '<message>' \
  --query 'pullRequest.{id:pullRequestId,status:pullRequestStatus,source:pullRequestTargets[0].sourceReference,destination:pullRequestTargets[0].destinationReference,sourceCommit:pullRequestTargets[0].sourceCommit,destinationCommit:pullRequestTargets[0].destinationCommit,mergeCommitId:pullRequestTargets[0].mergeMetadata.mergeCommitId,isMerged:pullRequestTargets[0].mergeMetadata.isMerged}' \
  --output json
```

If CodeCommit returns `PullRequestApprovalRulesNotSatisfiedException`, stop. Do not delete the source branch. Tell the user approvals are still pending.

## Delete Source Branch

Only after the merge response shows `isMerged: true`, verify both branches:

```bash
aws codecommit get-branch --repository-name <repo> --branch-name <destination-branch> --profile <profile> --region <region>
aws codecommit get-branch --repository-name <repo> --branch-name <source-branch> --profile <profile> --region <region>
```

Then delete only the source branch:

```bash
aws codecommit delete-branch \
  --repository-name <repo> \
  --branch-name <source-branch> \
  --profile <profile> \
  --region <region> \
  --query 'deletedBranch.{name:branchName,commitId:commitId}' \
  --output json
```

Final verification:

```bash
aws codecommit get-pull-request --pull-request-id <pr-id> --profile <profile> --region <region>
aws codecommit get-branch --repository-name <repo> --branch-name <destination-branch> --profile <profile> --region <region>
aws codecommit get-branch --repository-name <repo> --branch-name <source-branch> --profile <profile> --region <region>
```

Expected final state:

- PR is `CLOSED`
- `isMerged` is true
- destination branch exists and points at the merge commit
- source branch lookup returns `BranchDoesNotExistException`

## Reporting

Report the exact PR id, merge commit id, destination branch, deleted source branch, and verification results. If any step is blocked, include the exact error and state that no branch cleanup was performed.
