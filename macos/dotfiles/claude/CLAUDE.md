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

### tmux navigation to reinforce
Same spirit as the input-editing keys — nudge opportunistically when the user is switching between projects/contexts or clearly has more than one tmux session running (don't force it).

- **`prefix + (` / `prefix + )`** — switch to the previous / next tmux session (learned 2026-06-27). `prefix + s` opens the interactive session tree to pick one directly.

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

### Talking to a Claude session on the devbox (`ssh devbox`)

**The devbox session owns its own work.** This is a channel for communication
and advice, not a remote control: messages carry context, not orders. When
something genuinely needs to change, the escalation originates from the Mac,
but the decision on that box stays with the session that lives there. The
delivery preamble is worded accordingly, and `devbox-inbox-test` guards the
wording — if it ever drifts back to imperatives, the channel has quietly become
something else.

Do **not** drive it with tmux keystrokes. That is synthetic input to a UI and it
fails three ways: swallowed by permission prompts, the agent-selection overlay
steals the Enter that should submit, and `C-u` wipes text the human had queued.
There is a real inbox instead:

```bash
# `ssh devbox devbox-inbox ...` does NOT work: ssh runs a non-login,
# non-interactive shell, so ~/.profile never puts ~/.local/bin on PATH.
# Wrap every call in a login shell.
ssh devbox 'bash -lc "devbox-inbox list"'                # queued / delivered / replies
ssh devbox 'bash -lc "devbox-inbox read"'                # replies from the session
ssh devbox 'bash -lc "devbox-inbox show 3"'              # re-read last 3 delivered
ssh devbox 'bash -lc "devbox-inbox send -"' < msg.md     # queue a message from a file
ssh devbox 'bash -lc "devbox-inbox send -"' <<<'text'    # ...or a one-liner
ssh devbox 'bash -lc "devbox-inbox send --to int-test -"' < msg.md   # one session only
```

**Always use the stdin forms.** Inline `send 'text'` nests quoting three deep
through `ssh` → `bash -lc` → the script, and a single apostrophe in the text
closes the quote. The remainder used to be dropped on the floor: on 2026-08-07 a
session's reply reached the Mac truncated mid-word with nothing reporting it.
Extra argv is now joined and warned about, but stdin is the only byte-exact form.

**Address the message whenever more than one session runs on that box.** An
unaddressed message is a broadcast, and whichever session's hook fires first
takes it — the others never see it. On 2026-08-07 one broadcast was picked up by
two sessions, both started the same phase, and one helm-converged the cluster
underneath the other's passing test run. `--to NAME` delivers to exactly one
session; the name is the tmux pane title, which a session reports with
`devbox-inbox whoami`. A message for a session that never runs stays queued
rather than being eaten, and `list` shows who each one is waiting for. Replies
are stamped with the sender, so you never have to infer it from the prose.

Delivered by hook, never polled: `Stop` blocks a session that is about to go
idle and hands the message over; `PostToolUse` injects mid-task without
blocking, so advice lands within seconds of its next tool call. The session
replies with `devbox-inbox reply '...'`, which the delivery text tells it — so
the reply direction needs no setup on its end.

**An empty queue means delivered, not lost.** The hook pushes content straight
into the session's context and archives the file, so `list` legitimately shows
nothing queued afterwards. Use `show N` to re-read. Never invoke
`devbox-inbox-hook` by hand to "check" delivery: it *consumes* the queue, and
the message the live session was about to receive is gone.

**The one limitation worth knowing: an already-idle session receives nothing.**
Hooks are event-driven, and a session sitting at its prompt emits no events, so
a queued message waits until it next does a turn. Nudging it has to be a
*human* keypress. `tmux send-keys` cannot submit that pane — verified
2026-08-07: `Enter`, `C-m`, and text+`Enter` in a single burst all failed to
submit, while literal characters and `BSpace` landed fine, so the transport
works and the submit key specifically is swallowed. Worse, a burst containing
`Enter` can *clear* text the human had queued in the prompt box. Type it
yourself, or just let the message ride until the session's next turn.

### Other devbox-only helpers (all in `~/.local/bin`, installed by restore.sh)

```bash
devbox-drift                 # what no longer matches the repo; exits 1 on drift
devbox-capture --pkg X 'why' # record a package/config fix at the moment you make it
devbox-worktree-rm <path>    # `git worktree remove` CANNOT work in a sandboxed
                             # session — the sandbox bind-masks .gitmodules and
                             # .git/worktrees/<n>/{config.worktree,commondir} and
                             # recomputes the list every Bash call, so retrying
                             # and --force never help. This removes it through a
                             # container, which runs outside the sandbox.
```

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

Codex CLI lives at the mise install (`which codex`; v0.144.1 as of 2026-07-13). Key flags: `-s read-only|workspace-write|danger-full-access`, `-C <dir>` working root, `--output-last-message <file>` for the clean final answer, `--json` for JSONL events, prompt from stdin with `-`.

**Posting the verdict — approve (or request-changes) WITH inline comments in one atomic review.** `gh pr review --approve` can only attach a top-level body; it cannot anchor line comments. Use the REST reviews endpoint so the summary + every inline note + the approval land as a *single* review (not a scattered set):

```bash
HEAD_SHA=$(gh pr view <n> --repo <owner>/<repo> --json headRefOid -q .headRefOid)
# Write the payload to a file (avoids shell-escaping the bodies). event: APPROVE|REQUEST_CHANGES|COMMENT.
# Each comment: path + line + side:"RIGHT" + body. commit_id MUST be the head SHA.
cat > /tmp/review.json <<JSON   # (or Write tool)
{ "commit_id": "$HEAD_SHA", "event": "APPROVE", "body": "<summary>",
  "comments": [ { "path": "pkg/foo.go", "line": 111, "side": "RIGHT", "body": "<nit>" } ] }
JSON
gh api -X POST /repos/<owner>/<repo>/pulls/<n>/reviews --input /tmp/review.json \
  --jq '{state,html_url}'
# Verify anchors landed: gh api /repos/<owner>/<repo>/pulls/<n>/comments \
#   --jq '.[]|select(.pull_request_review_id==<id>)|"\(.path):\(.line)"'
```

Gotcha: an inline comment only anchors to a line that is **part of the PR diff** (RIGHT side = added/context line). For a **new file** every line qualifies; for an edited file, target an added/changed line or the POST 422s. Approving/outward-facing → needs explicit user go-ahead first (per the confirm-before-outward-action rule).

### OrbStack — docker.sock missing / VM wedged (external-drive I/O stall)

Symptom: `docker` / `docker compose` fails with `~/.orbstack/run/docker.sock: no such file or directory`, or `orb status`/`docker ps` hang forever. The socket is a **symptom**: it only exists while OrbStack's VM engine is up. Root cause (diagnosed 2026-07-02): OrbStack's VM disk (`data.img.raw`) lives on the external drive (`AchtungAndy` → `OrbStack.dmg.sparseimage` → `/Volumes/OrbStackData/orbstack-data/`); a brief drive stall wedges the guest kernel on block I/O (`virtio-fs failed -22`, hung task in `__swap_writepage → virtio_queue_rq` in `~/.orbstack/log/vmgr.log`). All volumes stay mounted — it is NOT a "disconnected drive" problem; don't remount anything.

```bash
# 1. Recover: graceful engine restart (worked cleanly, ~17s each)
orb stop
orb start

# 2. GOTCHA — `orb start` may exit 1 with "start VM: timed out waiting for VM to start".
#    That is a FALSE ALARM (CLI gives up waiting on the privileged helper); check vmgr.log —
#    if the guest kernel booted and containers are starting, the VM is actually fine.

# 3. Verify by probing, never by exit code (docker engine warms up ~30s after boot):
orb status      # "Running"
orb list        # machines up
docker ps       # give it a retry after ~30s
```

Wrap every `orb`/`docker` probe in a watchdog while diagnosing — a wedged engine makes them hang forever, and macOS has no `timeout` (check `gtimeout`, else bash loop):

```bash
orb stop & pid=$!
for i in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
kill -0 "$pid" 2>/dev/null && kill "$pid"    # still hung → kill, escalate to force-stop
```

Related but different: testcontainers-based Go integration tests failing with "rootless Docker not found" while the socket EXISTS → that's env vars, not a restart: `DOCKER_HOST=unix://$HOME/.orbstack/run/docker.sock TESTCONTAINERS_RYUK_DISABLED=true`.

### Codex plugin broken after a codex CLI upgrade (stale broker/app-server)

Symptom: after `mise` upgrades codex (or the model in `~/.codex/config.toml` changes), Claude sessions can't call the codex plugin. Root cause: the plugin persists a **shared per-project broker** in `~/.claude/plugins/data/codex-openai-codex/state/<project-hash>/broker.json`; `ensureBrokerSession` reuses it as long as its socket answers, and the broker's long-lived `codex app-server` child keeps executing the **deleted** old binary image (unlinked file stays alive in memory — mise upgrade doesn't kill it).

```bash
# 1. Confirm: find broker + app-server, check which binary the app-server actually runs
ps aux | grep -E 'app-server-broker|codex app-server' | grep -v grep
lsof -p <app-server-pid> | grep txt          # shows the (possibly deleted) mise install path

# 2. Kill the stale pair (broker + its codex app-server child)
kill <broker-pid> <app-server-pid>

# 3. Clear persisted broker state so next session spawns fresh (also rm the cxc-* session dirs it points at)
rm ~/.claude/plugins/data/codex-openai-codex/state/*/broker.json

# 4. Verify: plugin setup check + model smoke test
node ~/.claude/plugins/cache/openai-codex/codex/1.0.0/scripts/codex-companion.mjs setup --json
codex exec -s read-only 'Reply with exactly: OK'
```

Notes: the broker spawns `codex app-server` from PATH at spawn time (no pinned path), so once the stale pair is dead everything self-heals on the next plugin call. `hook: Stop Failed` in `codex exec` output is the plugin's disabled stop-review-gate hook — benign.

**Review-content tip:** for webhook-HMAC / signature reviews, first identify **which layer** the signature belongs to, because it flips the self-signed-test verdict:

- **Gateway / perimeter HMAC** = *your service's own* signing contract with the sender (e.g. an `x-vendor-signature: t=…,v1=…` header signed over `{t}.{raw_body}`). You define the wire format, so **self-signed tests are legitimate** — the test computing the expected digest with `crypto/hmac` independently of the production call site is the correct pattern, not a gap.
- **Per-vendor / provider in-body scheme** = the *provider's* native signature (e.g. a provider TID, or a provider `X-Signature` header) verified inside the adapter. Here the bug-vs-by-design verdict hinges on whether the test signs against a *real captured provider signature* or *self-signs* — self-signed tests can't prove the provider's true signing input, so make it a confirm-with-author item, never a guess.

When both layers coexist (gateway in front, adapter in-body as defense-in-depth), review them separately; don't apply the "self-signed proves nothing" caution to the gateway layer. Cheap security checks worth confirming on a gateway HMAC: replay-window is an *independent* layer from the MAC (guard against `time.Duration` saturation on a far-future `t` — `-math.MinInt64 == math.MinInt64`, still negative, slips a naive `|skew|>window`), fixed-length check on the hex digest *before* `hex.DecodeString` (no large-alloc DoS), `hmac.Equal` for constant-time compare, and fail-closed wiring (route unmounts unless every auth dep is non-nil).

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
