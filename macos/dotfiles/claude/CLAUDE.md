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

## How you write

A hard requirement, not a preference.

Write in **ASD-STE100 Simplified Technical English**. Apply Zinsser's four
principles: **simplicity, brevity, clarity, humanity**. This governs everything
you produce:

- replies to me in session
- PR titles and descriptions
- review summaries and inline review comments
- commit messages
- issue text, status reports and handoffs
- documentation, READMEs and code comments

The rules that carry the most weight:

- **One idea per sentence.** Instructions stay under 20 words, descriptions
  under 25. A sentence that needs a semicolon is usually two sentences.
- **Active voice, and name the actor.** "The gate refuses the post", not "the
  post is refused". Passive voice hides who acts, and in a review comment the
  actor is most of the content.
- **One word, one meaning.** Pick a term and keep it. A `worktree` stays a
  `worktree` — never a "checkout", a "copy" or a "tree". A synonym reads as a
  distinction, and the reader then hunts for one that is not there.
- **Cut every word that does no work.** "It should be noted that the test
  fails" is "the test fails". Delete *actually*, *simply*, *just*, *basically*,
  *in order to*, *at this point in time*.
- **No noun stack longer than three words.** "review payload anchor validation
  failure" becomes "the anchor validation failed for the review payload".
- **Keep the articles and the verbs.** "Gate refuses post when evidence
  missing" is not brevity. It is a puzzle.
- **Present tense. Imperative for instructions.**
- **Numbers, not adjectives.** "Significantly faster" is an adjective.
  "3m14s, down from 15m" is a measurement.

**Humanity, for an agent, means something specific.** You are not a person, so
do not perform warmth. Write to a named reader. Own uncertainty in the first
person: "I could not verify this. The resolving text may be somewhere I did not
look." Never retreat into passive voice to avoid saying who is unsure. Hedged,
authorless prose costs the reader more than a plain "I do not know".

**Friendly is a stance, and politeness is one word, not a paragraph.** Use
*please*, *would* and *thanks* where a request needs marking as a request —
"please name the real window", "would you update the comment". They cost one
word and they do real work. Do not reach for warmth with praise or softeners:
"great work", "just a small nit", "I might be totally wrong here". Those add
words and grant nothing.

The stance carries the rest: assume the author had a reason, ask before you
conclude, and name your own uncertainty. Each of those is shorter than the
confident version, so friendly and concise pull the same way. They conflict
only when the warmth is decoration.

**Never grade another person's work.** "That is a fair trade", "good catch",
"this is a reasonable approach" — a passing mark is still a mark, and awarding
one claims a rank nobody gave you. Say what you observed and what you are
asking for. This binds hardest in a review, where the reader did the work.

**Cut every sentence that manages the reader's reaction.** They are the ones
that read as rude, and they are also the wordiest, so they cost twice:

- pre-empting an objection nobody made — "I am not asking you to change it"
  implies the reader was about to over-react
- invoking a third party for authority — "the next reader will need this" says
  your own judgement did not warrant the ask
- softening a finding you already verified, which makes the reader re-derive
  how sure you are

Delete the category. What remains is the observation, the evidence and the ask.

### What this rule does not mean

- **It is not a licence to review other people's prose.** The rule binds what
  you write. It never becomes a demand on an author whose code you review.
- **It does not shorten the evidence.** Brevity is a property of words, not of
  claims. A report loses when it drops the `path:line` anchor, the measured
  number, or the paragraph saying what the run does not prove.
- **It is not a mandate to rewrite existing files.** It applies to new text and
  to text you edit.

## Process

### Worktree-First (before the first edit, every time)
Do NOT code on the current checkout — not for a feature, not for a one-line fix. Before the first edit, create a git worktree branched off `main`:

```bash
git -C <repo> fetch origin main
git -C <repo> worktree add -b <task-slug> ../<repo>-<task-slug> origin/main
```

Then work in that worktree. "It is only one line" is precisely when this gets skipped and precisely when it costs the most: the primary checkout is now dirty, and everything downstream assumes it is not.

That assumption is load-bearing, not stylistic. `src-sync` skips any repo with modified tracked files, deliberately — a fast-forward into someone's edits is not safe unattended. So an edit made directly on `main` stops that repo pulling, silently, every hour, until a human notices. It went unnoticed for weeks on the devbox (0x58 PR #83). A worktree keeps the primary checkout clean, which keeps it a valid base to branch from and safe to fast-forward.

Worktrees are **siblings** of their parent checkout, never inside it. Exception: only skip this when the user **specifically asks** to work somewhere else (current branch, an existing worktree, a named branch).

**A hook enforces this now.** `worktree-guard` runs on every Edit and Write. It refuses a write to a **tracked** file in a checkout sitting on its default branch, and names the worktree command for that repo. An untracked file passes, because src-sync tolerates one. A feature branch and a detached review worktree pass. Anything it cannot decide passes: it fails open, so a broken guard never stops you working.

Claude Code's own `worktree.bgIsolation` covers background sessions only. This covers the interactive ones, which is where the rule kept breaking.

Deliberate exception: `touch ~/.claude/allow-main-edit` opens a **60-minute** window, and every edit through it says so on screen. The window closes itself — a permanent off switch goes invisible within a week.

**Clean up when the PR merges, and check against main often.** `worktree-sweep` does both:

```bash
worktree-sweep                 # merged worktrees, distance from origin/main, fetch age
worktree-sweep --fetch         # re-read origin first
worktree-sweep --remove        # remove the merged, clean ones; delete their branches
```

"Merged" means contained in `origin/main`, or a merged PR when `gh` can confirm one — a squash merge leaves no ancestry. It never removes a dirty worktree, the one you are standing in, or a branch it could not prove merged. A branch sitting exactly on `origin/main` reads as `fresh`, not merged: that is a worktree somebody just made.

It removes through `devbox-worktree-rm` on Linux when that exists, because a sandboxed session bind-masks the worktree metadata and plain `git worktree remove` cannot work there (see the Operations Runbook). On the Mac, `git worktree remove <path>` is fine.

The SessionStart hook reports the same three facts, so a stale worktree and a branch drifting behind main both surface before the first edit.

### Planning
Break complex work into 3-5 stages. Each stage: goal, success criteria, test cases.

**When the work has an issue or a PR, the plan lives there.** Post it with `gh-context --kind plan` before the first edit, and update that comment as stages land. See "Context goes to the ticket, not to memory" below. With no ticket, keep the plan in `IMPLEMENTATION_PLAN.md` and remove it when done.

`IMPLEMENTATION_PLAN.md` and `IMPLEMENTATION_PLAN-*.md` are **local-only working contracts**. Gitignore them; never `git add` (don't bypass with `-f`). Never reference them in commit messages, code comments, or PR descriptions — they don't exist for collaborators, and references rot fast as work progresses. Sprint context lives in the PR description; commit messages explain the change directly.

### Context goes to the ticket, not to memory

The PR or the issue is the home for the context around it. The comment holds the content. Memory holds a pointer to the comment.

Post to the ticket when you:

- plan the work, before the first edit
- finish a stage, or park the work mid-way
- measure something the next person cannot re-derive — a control run, a merge order, a gap the tests cannot see
- end a branch — the follow-ups, the known gaps, what the next person must watch

`gh-context` does the posting. Each (ticket, kind) owns **one** comment, and a re-run edits that comment instead of stacking another:

```bash
gh-context --read                        # what earlier sessions posted. Read this first.
gh-context --kind plan      -F -         # kinds: plan | status | findings | followups
gh-context --kind status    -m 'one line'
gh-context --kind followups -F notes.md  # post-merge considerations, before you call it done
gh-context --scan-only      -F draft.md  # check the text, post nothing
```

It resolves the pull request from the current branch. Name an issue explicitly (`--issue N`) — a branch name is a guess, and a work log on the wrong ticket is worse than a question.

**It scans the body before anything leaves the machine.** A secret-shaped match refuses on every repo, and `--public` does not override it. On a public repo a home path, a username, an internal hostname or an email address also refuses; `--public` is how you say you meant to publish it. The scan names the line and never rewrites your text.

Memory then keeps three things: a one-line pointer to the ticket that holds the state, machine-local gotchas no ticket wants, and private preferences. When you touch a fat project memory note, shrink it to a pointer and move the content to the ticket.

**Why:** a note in `~/.claude` is invisible to the reviewer, to the team and to the next agent. A go-monorepo memory note carried a merge-order hazard between two open PRs and labelled it, in its own text, "not in either PR" (2026-08-03).

Work with no ticket keeps its context in memory. That is what memory is for. Open an issue when the work deserves one.

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
session. **Name a session before addressing it** — a pane with no name answers to
its opaque pane id (`pane-14`):

```bash
ssh devbox 'tmux set-option -p -t main:1.1 @inbox_id int-test'
```

That is a pane *option*, not the pane title. Do **not** use the pane title: Claude
Code rewrites it as its work changes, so a session named `int-test` started
answering to `_ Manage session inbox and sub-agent lifecycle` within minutes
(2026-08-07). `@`-prefixed options are tmux's user namespace and no application
touches them. `devbox-inbox whoami` reports the resolved name and, when it is a
fallback, prints the command above. A message for a session that never runs stays queued
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
                             # never helps and --force makes it WORSE: it deletes
                             # tracked files before failing on the masked
                             # metadata (observed 2026-08-09). This removes it
                             # through a container, which runs outside the
                             # sandbox. Also handles a worktree whose directory
                             # is already gone (stale metadata after a reboot) —
                             # run it from inside the owning repo for that case.
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

**The shape of an inline comment: issue, question, expected.** Three labelled parts, then the verdict on its own line. The labels let the author answer the middle part without re-reading the first, and they stop a comment drifting into a verdict essay.

- **Issue** — what you observed: the anchor, the quoted text, or the control run you ran. What the code does, not what the author got wrong.
- **Question** — what you could not settle from the tree. Drop this part when nothing is left to ask. Never keep it as a rhetorical wrapper.
- **Expected** — the behaviour you ask for, marked as a request (*please*, *would*). One sentence.
- Then `Non-blocking.` or `This blocks: <one clause>`, on its own line. The labels and the request marker lower the temperature on purpose, so this line is what stops a blocking defect reading as optional. It is not optional itself.

The review body takes four headings — what I checked, findings (`N inline, M blocking`), what I could not check, tests — and **a heading names a section, never a verdict**. Findings live in the inline threads, so do not restate them in the body. See "How you write" above for the three moves that make a comment read as rude; each one is also the wordiest sentence in the comment, so cutting them shortens it. Cut prose, never a `path:line`, a control run or a quoted contradiction.

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

### `codex exec` exits 0 and produces nothing — a shadowed binary, not an empty review

Diagnosed 2026-08-13 on the devbox, after two sessions each lost a review run to it. Symptom: `codex exec -s read-only --output-last-message out.md '…'` returns **rc=0**, prints only node circular-dependency warnings, and writes **no** `out.md`. Nothing in that signature says "failure", which is what makes it dangerous — rc=0 with no findings is indistinguishable from a clean review, so the next step "validates" a report that does not exist.

Root cause: an npm package **also named `codex`** — a static-site generator, v0.2.3, last touched 2013 — installs a `codex` bin into node's global prefix. Where both mise's `codex` tool and mise's `node` provide a bin of that name, the shim resolves to the node one:

```bash
mise ls | grep codex                 # says 0.144.1 — reassuring and irrelevant
mise which codex                     # …/installs/node/22/bin/codex   ← the impostor
codex --version                      # 0.2.3            (real one: codex-cli 0.144.1)
npm ls -g --depth=0                  # codex@0.2.3 sitting next to npm and corepack
```

```bash
npm rm -g codex && mise reshim        # removes only the 2013 doc generator
mise which codex                      # …/installs/codex/0.144.1/bin/codex
```

Safe to remove: npm's global root held only `codex`, `corepack`, `npm`, so nothing else loses a bin, and mise's real codex lives in its own prefix (`installs/codex/<ver>`, npm backend) that `npm rm -g` cannot reach. Verify with `devbox-drift` — it should report *no* drift afterwards, because a rebuilt box installs codex from the mise config and never had the impostor.

Three general lessons, all of which cost a session each:

- **Assert a tool's identity, not its presence.** `command -v codex` passes for the impostor; `codex --version | grep codex-cli` does not. Any flow depending on an external tool should check the version string, then fall back to the absolute install path (`~/.local/share/mise/installs/<tool>/latest/bin/<tool>` — the `latest` symlink, so it survives version bumps).
- **Judge a run by its artifact, never by `$?`.** Use `--output-last-message` and require the file to be non-empty and above a byte floor; a 2-byte smoke `OK` and a real report both exit 0.
- **A release-age gate does not defend against this.** `minimum_release_age` (3d on the devbox) screens version *freshness*; the impostor is twelve years old. Name confusion and typosquats are orthogonal to maturity floors, and a floor can give false comfort against them.

Related but different: if `codex` resolves correctly and the *plugin* still misbehaves after an upgrade, that is the stale broker above, not this.

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
