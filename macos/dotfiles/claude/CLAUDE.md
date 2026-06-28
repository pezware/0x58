# Development Guidelines

## Knowledge Book

Operational gotchas and patterns discovered during work — see [`~/.claude/knowledge/`](knowledge/):

- [`bash-gotchas.md`](knowledge/bash-gotchas.md) — Pitfalls in sourced scripts (cat/bat alias, heredocs)

## Claude Code TUI Reminders

User runs Claude Code in fullscreen rendering mode (`tui: fullscreen` in `~/.claude/settings.json`). Surface these from time to time when relevant — not every session, but when the user is reviewing long output, asking how to scroll/search, or scrolling back through a long conversation:

- **`Ctrl+o`** toggles transcript mode: `less`-style nav (`/` to search, `n/N`, `j/k`, `g/G`, `Ctrl+u/d` for half-page), `q` or `Esc` to exit.
- **`[` inside transcript mode** dumps the full conversation into the terminal's native scrollback — then `Cmd+f` and tmux copy-mode can search it.
- **`v` inside transcript mode** opens the conversation in `$EDITOR`.

### Input-editing keys to reinforce
User is building muscle memory for these control bytes and asked to be nudged toward them. When a natural opening appears (they're about to retype/clear a line, want a newline, are scrolling back), drop a brief reminder — opportunistically, not every turn. User already has `Ctrl+c/d/l/z/a/e/r/b` down, so do NOT remind on those.

- **`Ctrl+J`** — insert a newline (their kitty can't send Shift+Enter; `term xterm-256color` masks the modified-key encoding).
- **`Ctrl+U`** — kill the entire input line.
- **`Ctrl+W`** — delete the previous word.
- **`Ctrl+K`** — delete from cursor to end of line.
- **`Ctrl+O`** — toggle transcript mode (see above).

## Principles
** Think Before Coding
** Read Before You Write
** Goal-Driven Execution
** Simplicity First
** Surgical Changes
** Tests Verify Intent
** Fail Loud

Incremental > big-bang. Study before building (find 3 similar patterns). Boring > clever. Composition > inheritance. Explicit > implicit. I/O-aware (disk/network are the bottleneck).

Priority: testability > readability > consistency > simplicity > reversibility.

## Process

### Worktree-First (start of any new batch of work)
When asked to start a **group of new tasks** (a feature, a multi-step change, a fresh batch of work), do NOT code on the current checkout. First create a git worktree branched off `main`:

```bash
git -C <repo> fetch origin main
git -C <repo> worktree add -b <task-slug> ../<repo>-<task-slug> origin/main
```

Then work in that worktree. This keeps the primary checkout on whatever it was and isolates the new work on a clean branch from `main`. Exception: only skip this when the user **specifically asks** to work somewhere else (current branch, an existing worktree, a named branch). Tear down with `git worktree remove <path>` when the work has landed.

### Planning
Break complex work into 3-5 stages in `IMPLEMENTATION_PLAN.md`. Each stage: goal, success criteria, test cases. Remove when done.

`IMPLEMENTATION_PLAN.md` and `IMPLEMENTATION_PLAN-*.md` are **local-only working contracts**. Gitignore them; never `git add` (don't bypass with `-f`). Never reference them in commit messages, code comments, or PR descriptions — they don't exist for collaborators, and references rot fast as work progresses. Sprint context lives in the PR description; commit messages explain the change directly.

### Implementation
1. Study existing patterns → 2. Write failing test → 3. Minimal code to pass → 4. Refactor with tests green → 5. Commit (explain "why")

### When the User Provides a Plan
Execute it as-is. Do not re-plan or restructure unless asked. Flag concerns inline.

### When Stuck (3-attempt limit)
After 3 failures, STOP. Document what failed. Research 2-3 alternatives. Try a different angle.

## Standards

### Commits

Every commit must compile, pass all tests, and include tests for new functionality. Run formatters/linters before committing. Never use `--no-verify`.

### Tests

Test behavior, not implementation. One assertion per test. Deterministic. Use existing test helpers. Never disable a failing test — fix it.

### Errors

Fail fast with context. Handle at the appropriate level. Never silently swallow.

### Tooling

Use the project's existing build system, test framework, and formatter/linter. Don't introduce new tools without strong justification.

### Definition of Done

- [ ] Tests written and passing
- [ ] Code follows project conventions
- [ ] No linter/formatter warnings
- [ ] Commit messages explain "why"
- [ ] No TODOs without issue numbers


## Compact Instructions

When compressing, preserve in priority order:

1. Architecture decisions (NEVER summarize)
2. Modified files and their key changes
3. Current verification status (pass/fail)
4. Open TODOs and rollback notes
5. Tool outputs (can delete, keep pass/fail only)

---

## Operations Runbook

### GitHub Actions - Force Cancel Stuck Workflow

```bash
gh run list --repo <owner>/<repo> --limit 5
gh api -X POST /repos/<owner>/<repo>/actions/runs/<RUN_ID>/force-cancel
```

### Terraform - Stuck Resource Deletion

```bash
terraform force-unlock -force <LOCK_ID>
terraform state rm '<resource.address>'
terraform apply -var-file=<tfvars>
```

### Terraform - Avoid Downtime on Resource Renames

```hcl
moved {
  from = kubernetes_deployment.app
  to   = kubernetes_deployment_v1.app
}
```

Apply once, then remove the moved blocks.

### Git Rebase with Signed Commits (Yubikey/SSH)

Repo requires all commits to have verified signatures. A normal rebase (`git rebase origin/main`) creates unsigned commits, which GitHub will reject on push. Two-step workaround:

```bash
# Step 1: Rebase without signing (avoids 12 Yubikey touches mid-rebase)
git -c commit.gpgsign=false rebase origin/main

# Step 2: Re-sign all rebased commits (one Yubikey touch per commit)
git rebase --exec 'git commit --amend --no-edit -S' HEAD~N   # N = number of commits

# Step 3: Force push
git push --force-with-lease
```

### gh CLI Safety

- NEVER pipe `gh api` directly to `python3` — empty/error responses cause JSONDecodeError
- Prefer `gh api --jq` or `gh run view --json --jq` over external parsing
- When Python IS needed: save to file first, check `$?`, then parse
- NEVER use `2>&1` when piping to a parser — error text becomes parser input
- For workflow-file-level errors (0 jobs): `gh run view --web` is the only way to see the error

### gh PR Create — Body Formatting

Heredoc inside `$(cat <<'EOF' ... EOF)` fails with bash escaping in `gh pr create --body`. Use a plain double-quoted string instead:

```bash
gh pr create --title "short title" --body "## Summary

- First point
- Second point

## Test plan

- [ ] Step one
- [ ] Step two"
```

Newlines work fine inside double-quoted strings. Avoid single quotes, backticks, or `$` in the body text (escape if needed).

### Reviewing a PR/branch in an isolated worktree + synchronous Codex cross-check

Review a feature branch **without** moving your primary checkout off `main`, and run Codex with full visibility (the background-Agent path is NOT pollable — `TaskOutput`/`TaskList` return "No task found" for its IDs and there's no `SendMessage` tool, so you can't observe its live state; prefer running `codex exec` yourself).

```bash
# 1. Keep the main repo on main; isolate the branch in a worktree.
git -C <repo> fetch origin <feature-branch>
git -C <repo> worktree add /tmp/wt-<slug> <feature-branch>      # tracks origin/<branch>
#   (if the local branch name is taken: worktree add -b review/<slug> /tmp/wt-<slug> FETCH_HEAD)

# 2. Run Codex synchronously, read-only sandbox, capture the final report.
#    Prompt via stdin ('-') to avoid shell-escaping; -C sets the working root.
codex exec -s read-only -C /tmp/wt-<slug> \
  --output-last-message /tmp/codex-report.md \
  - < /tmp/codex-prompt.md
#   read-only is fine for review; if Codex must `go test`, the build cache ($GOCACHE,
#   usually ~/Library/Caches/go-build) is OUTSIDE the workspace, so prefer running tests
#   yourself and telling Codex they're already green + to focus on static analysis.

# 3. Read the report, then tear down — leaves the main repo untouched on main.
git -C <repo> worktree remove /tmp/wt-<slug> --force
git -C <repo> worktree prune
git -C <repo> branch -D <feature-branch>     # delete the auto-created local tracking branch
```

Codex CLI lives at the mise install (`which codex`; v0.125.0 used here). Key flags: `-s read-only|workspace-write|danger-full-access`, `-C <dir>` working root, `--output-last-message <file>` for the clean final answer, `--json` for JSONL events, prompt from stdin with `-`.

**Review-content tip:** for webhook-HMAC / signature reviews, the bug-vs-by-design verdict hinges on whether the tests sign against a *real captured provider signature* or *self-sign* — self-signed tests can't prove the provider's true signing input, so make it a confirm-with-author item, never a guess.

---

## Post-Task Learning Capture

After completing a major task, Claude MUST ask:

> "Should we capture what we learned? Options:
> 1. **Runbook entry** — operational recipe (add to Operations Runbook above)
> 2. **Skill pattern** — reusable technique (`~/.claude/skills/<skill>/patterns/`)
> 3. **Memory note** — project context (MEMORY.md or topic file in memory/)
> 4. **Skip**"

**Triggers:** debugging >3 steps, infra/deployment work, perf optimization, security fixes, external service integration, failed first attempts, significant feature work.

**Capture specifics:** exact commands/config that worked, symptoms vs root cause, why the obvious approach failed, version/flag gotchas, useful doc links.
