---
name: codecommit-pr-create
description: Use when asked to create an AWS CodeCommit pull request for a Jira ticket from the current local branch.
---

# CodeCommit PR Creation

Open one CodeCommit PR only after the Jira issue, current source branch, AWS context, and destination have been resolved. On a blocker, report the exact reason and make no subsequent mutation.

## Rules

- Use `nih_mgmt` if the user explicitly requests it. Otherwise discover profiles with `aws configure list-profiles` and test repository access, following `codecommit-pr-merge` conventions.
- Treat AWS reads, branch creation, and PR creation as subject to the active environment's normal escalation and approval controls.
- A detached HEAD, no current branch, no CodeCommit remote, unpushed source, source missing in CodeCommit, or source equal to destination is a blocker.
- **REQUIRED SUB-SKILL:** Use `secrets-credential-scanning` for the destination-to-source commit range before opening the PR. A blocking, non-allowlisted finding stops the workflow.
- Never create, overwrite, or attempt to create `main`. Local `main` is never a release-branch base.

## Discover and Confirm the Source

1. Load the Jira issue using the supplied key and record its uppercase key and canonical **Jira Summary**. Stop if either is unavailable.
2. Inspect the local repository and current branch. Resolve the CodeCommit repository from `origin` (or the selected CodeCommit remote); ensure the remote identifies a single repository.
3. Discover a usable AWS profile and region, then verify the repository and source branch exist remotely. Record the local `HEAD` and remote source commit ID; they must be identical, so an unpushed local commit is a blocker. For example:

   ```bash
   git branch --show-current
   git rev-parse HEAD
   git remote -v
   git ls-remote --heads origin <source-branch>
   aws codecommit get-repository --repository-name <repo> --profile <profile> --region <region>
   aws codecommit get-branch --repository-name <repo> --branch-name <source-branch> --profile <profile> --region <region> --query 'branch.commitId' --output text
   ```

4. Present the repository, AWS profile/region, detected source branch, and remote source commit. Require explicit user confirmation before deriving a destination or creating anything. If the local branch, local `HEAD`, or remote source commit changes after confirmation, stop and request confirmation again.

## Derive Destination and Title

After confirmation, normalize the Jira Summary into `<slug>`: lowercase words separated by one hyphen, punctuation removed, and repeated separators collapsed. Keep the Jira key uppercase.

| Source branch condition | Destination | Pull-request title |
| --- | --- | --- |
| Name starts with `release` | `main` | `<JIRA-KEY> <Jira Summary> - merge to main` |
| All other source branches | `release/<JIRA-KEY>-<slug>` | `<JIRA-KEY> <Jira Summary>` |

Show the derived destination and title. Verify that source and destination differ.

## Ensure the Destination Exists

For a release source, require that remote `main` exists; do not create it.

For every other source, look up the derived release branch remotely. If it is absent:

1. Read the current remote CodeCommit `main` branch commit ID; stop if `main` is absent.
2. Immediately recheck that the release branch is still absent. If it appeared, stop on the race/conflict rather than altering it.
3. Create the release branch from that exact remote `main` commit ID:

   ```bash
   aws codecommit get-branch --repository-name <repo> --branch-name main --profile <profile> --region <region> --query 'branch.commitId' --output text
   aws codecommit get-branch --repository-name <repo> --branch-name <release-branch> --profile <profile> --region <region>
   aws codecommit create-branch --repository-name <repo> --branch-name <release-branch> --commit-id <remote-main-commit> --profile <profile> --region <region>
   ```

   A successful creation is the only case to report a created release branch. Do not substitute a local `main` checkout or any local commit.

Before creating the PR, verify source and destination both exist remotely again and record their current commit IDs. Recheck that the local branch and `HEAD` are unchanged and that the remote source still equals the confirmed local `HEAD`; otherwise stop rather than creating a PR from a changed source.

```bash
aws codecommit get-branch --repository-name <repo> --branch-name <source-branch> --profile <profile> --region <region> --query 'branch.commitId' --output text
aws codecommit get-branch --repository-name <repo> --branch-name <destination-branch> --profile <profile> --region <region> --query 'branch.commitId' --output text
```

## Prevent Duplicates and Create the PR

Paginate through all open PR identifiers and inspect candidates with `get-pull-request`. Compare each candidate's `sourceReference` and `destinationReference` with `refs/heads/<source-branch>` and `refs/heads/<destination-branch>`. If an existing open PR has the same pair, stop and report its identifier; do not create a duplicate.

Run the required secrets scan using the current remote destination and source commits. If it passes, create the PR with the exact derived title and fully-qualified CodeCommit references:

```bash
SECRETS_SCAN_BASE=<destination-commit> SECRETS_SCAN_HEAD=<source-commit> \
  /path/to/secrets-credential-scanning/scripts/scan-secrets.sh
```

```bash
aws codecommit create-pull-request \
  --title '<JIRA-KEY> <Jira Summary>' \
  --targets repositoryName=<repo>,sourceReference=refs/heads/<source-branch>,destinationReference=refs/heads/<destination-branch> \
  --profile <profile> \
  --region <region> \
  --query 'pullRequest.{id:pullRequestId,title:title,status:pullRequestStatus,repository:pullRequestTargets[0].repositoryName,source:pullRequestTargets[0].sourceReference,destination:pullRequestTargets[0].destinationReference}' \
  --output json
```

Use the release-source title form (`<JIRA-KEY> <Jira Summary> - merge to main`) when the destination is `main`.

## Report

Report the repository, AWS profile/region, source, destination, derived title, created release branch (when applicable), and PR identifier/URL. For any blocker, report the exact reason, whether any release branch was already created, and that no later mutation was performed.
