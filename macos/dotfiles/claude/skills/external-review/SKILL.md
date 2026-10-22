---
name: external-review
description: >-
  Get a code review from a model outside this session: agy (Gemini 4 Argon)
  first, then codex, then a fresh Claude. Verify each finding against the code
  before you report it. Use when the user asks for an external, second-opinion
  or cross-model review of a pull request, a branch or a diff.
---

# External review

`external-review` sends one diff to one outside reviewer and writes the report to
a file. The reviewer proposes findings. You decide which ones are true.

## 1. Run it

```bash
external-review --pr 2635                # a PR, at its head, in a detached worktree
external-review                          # this branch against origin/main
external-review --base origin/release    # another base
external-review --backends claude        # one backend, or a list: agy,claude
```

Run it with `run_in_background: true`. A review takes 2 to 11 minutes. It prints
the report path. `run.json` in the same directory names the backend that
answered, the reviewed tree, the time, the tokens and the quota.

The order is agy, then codex, then claude. A backend that is missing, signed
out, under its budget floor or silent falls through to the next one.
`EXTERNAL_REVIEW_BACKENDS` sets the order for a whole session.

| Exit | Meaning |
|---|---|
| 0 | A report exists. |
| 1 | Every backend failed. stderr gives one reason per backend. |
| 2 | Bad usage, or nothing to review. |

On exit 1, tell the user which backends failed and why. Do not review the diff
yourself as a silent substitute.

## 2. Verify every finding

Measured on 2026-10-21 over three pull requests: codex's only finding on one of
them was false, and codex marked 4 of 4 findings "blocking" when none was. agy
had a wrong detail inside 2 of its 8 true findings.

For each finding:

1. Open the cited `path:line` in the reviewed tree (`.tree` in `run.json`). Read
   the code, not the reviewer's quote of it.
2. Reproduce it when you can: call the function, run the guard, grep the callers.
3. Check the claim against `origin/main` too. A PR's base can be stale: codex
   once cited a default that main had already fixed.
4. Give it a verdict: **holds**, **holds but latent**, **false positive** or
   **out of scope**. Grade the severity yourself.

Never relay a finding you did not verify. When you are not sure, say so in the
first person and name what you could not check.

## 3. Report

Give one table: finding, location, verdict, severity, evidence. Then one line:
backend, time, and quota used, taken from `run.json`.

Posting to GitHub is an outward-facing action. Get the user's go-ahead first,
then use the runbook's review format: Issue, Question, Expected, verdict line.

For a PR run, remove the worktree when you finish:
`git worktree remove --force <tree>`.

## Setup and failure modes

Read `references/backends.md` when a backend is skipped or fails, or when you
set up a new machine.
