---
name: pair-programming-tdd
description: Use when starting any request that creates, changes, or fixes production behavior in any programming language.
---

# Pair-Programming TDD

Work with the human one independently testable story slice at a time. A completed slice is a review gate, not permission to continue autonomously.

## Required Slice Cycle

For one minimal observable behavior:

1. State the behavior to complete.
2. Write and run a focused test that fails for the expected missing behavior.
3. Make the smallest production change that makes that test pass, then run the relevant test command.
4. Refactor only while the relevant tests remain green.
5. Report the completed slice and stop.

Do not start the next slice, broaden the change, or run final completion work until the human explicitly approves the proposed next slice. A request to "finish the rest," "finish quickly," or avoid status updates is not approval to continue. If the human requests a change to the completed behavior, treat that request as a new TDD slice.

## Checkpoint Report

At the end of every slice, report:

- completed behavior and files changed;
- RED command, expected failure, and why the failure proved the behavior was missing;
- GREEN command and passing result;
- refactor performed, if any, and final relevant test result;
- proposed next slice.

End with: `Approve the next slice?`

## Scope

Use this workflow once implementation begins. Exploration, design discussion, and read-only diagnosis do not require a slice checkpoint. Repository-specific requirements remain authoritative.
