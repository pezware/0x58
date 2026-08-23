---
name: devbox-workflow
description: Take work from a GitHub issue through worktree, signed commit, push, PR, tests and review on the Linux devbox. Use when working on pezware-devbox, or when a git/gh/test step fails there in a way that would not happen on macOS.
---

Run the full loop on the devbox: **issue → worktree → signed commit → push → PR →
tests → comment → review**.

The devbox can do all of it unattended. That is a deliberate posture, not an
accident — read [autonomy and its limits](patterns/autonomy-and-limits.md) before
assuming anything about what you may touch.

## First: confirm where you are

This file syncs to the Mac too, and several steps below are wrong there.

```bash
uname -s          # Linux = devbox rules apply;  Darwin = stop, use the Mac flow
```

On macOS, signing goes through Secretive and needs a Touch ID tap; `gh` uses the
Keychain. None of the mechanics below apply.

## The loop

**1 — Read the issue.** `gh` picks its token from the repository's owner, and it
reads that owner from `--repo`, from a `gh api` path, or from the origin remote.
Name the repo and it works from anywhere. Name none of them and it has no token.

```bash
~/.local/bin/gh issue view <n> --repo <org>/<repo> --json title,body,labels,milestone
```

**`gh` is the one tool that must not come from the mise shim.** `~/.local/bin/gh`
is the wrapper that selects the token; `~/.local/share/mise/shims/gh` is raw gh
with no credential at all, and answers `please run gh auth login` — an error that
reads like a broken install rather than a shadowed binary.

**Set PATH once, at the start of the session, with `~/.local/bin` in front.**
Your shell is non-interactive, so it starts with no mise tools *and* no `~/.local/bin`
— which is why reaching for `go` or `kubectl` pushes you to prepend the shims, and
why doing that naively shadows `gh`:

```bash
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
command -v gh      # MUST print /home/arbeitandy/.local/bin/gh — if not, fix PATH
```

Order is the whole point: shims first would give you raw `gh`. With this line you
can use plain `gh`, `go` and `kubectl` for the rest of the session and stop
thinking about it. If a `gh` command ever answers `please run gh auth login`, do
**not** run `gh auth login` and do **not** reach for a token — re-run
`command -v gh` and fix the ordering.

Three things that look like breakage and are not: `~/.config/gh/` is empty,
`$GH_TOKEN` is unset in your shell, and **gh itself tells you to log in**. The
wrapper injects the token into gh's own process at exec time, so the first two
are *always* true here even when gh works perfectly.

The third is the one that catches people, because it is gh's own voice:

```
To get started with GitHub CLI, please run: gh auth login
```

**That message is wrong on this box and following it is a dead end.** It means
only that no token was selected — almost always because you are not inside a
repo. `gh auth status` is useless here for the same reason: it reports on stored
credentials, and there are none by design.

On 2026-08-05 a session sat in `~/src/iden2`, ran gh, read that line, concluded
"gh isn't authenticated on this box" and stopped to ask the human — while gh one
directory down worked fine.

**Either of these gives the wrapper what it needs.** `--repo` wins over the
working directory, so you do not have to `cd` at all:

```bash
gh issue view 1160 --repo iden2-com/go-monorepo      # works from anywhere
cd ~/src/iden2/go-monorepo && gh issue view 1160     # uses the origin remote
```

`-R` and `--repo=owner/name` work too. Until 2026-08-05 the wrapper ignored the
flag entirely and looked only at the origin remote, so the first form failed from
outside a checkout — which is precisely how that session used it, and it was
right to.

The wrapper prints its own diagnosis ahead of gh's, so you should see the real
reason first. If you ever see gh's bare message with **nothing above it**, the
wrapper is not the `gh` you ran — check `command -v gh`, and if it is a mise shim
fix your PATH ordering. `gh auth login` is still not the fix.

**2 — Worktree off `main`.** Never work on the primary checkout.

```bash
git -C ~/src/<org>/<repo> fetch origin main
git -C ~/src/<org>/<repo> worktree add --no-track -b <task-slug> \
    ../<repo>-<task-slug> origin/main
cd ~/src/<org>/<repo>-<task-slug>
mise trust .        # a fresh worktree is untrusted; skipping this breaks EVERY mise tool
```

**`--no-track` is required.** Without it git writes upstream tracking into
`.git/config`, which the sandbox makes unwritable, and the command fails. The trap
is that it **creates the branch before failing**, so the obvious retry then dies
with `a branch named '<slug>' already exists` — pointing at a branch you appear to
have made twice rather than at the config write that actually failed. If you are
already in that state, attach to the existing branch instead of inventing a new
name:

```bash
git -C ~/src/<org>/<repo> worktree add ../<repo>-<task-slug> <task-slug>
```

**2a — Gather context, then write the plan.** Do this *in* the worktree, before
the first edit. Read the code the issue touches and find two or three existing
patterns to follow — this repo's conventions are not guessable from the issue
text, and matching them is most of what makes a PR reviewable.

Write the plan as `IMPLEMENTATION_PLAN.md` in the worktree root: 3–5 stages, each
with a goal and how you will know it worked. It is **gitignored and local-only** —
never `git add` it, never cite it in a commit message or PR body. Collaborators do
not have it, and references to it rot within a day.

Working several issues at once? Decide the branch shape before you start rather
than after. One worktree per PR is the default; issues share a branch only when
they share a change. Otherwise review is harder for everyone and a revert takes
down work that was fine.

**3 — Work, then commit signed.** Signing works with no agent and no tap, because
`user.signingkey` is a **path** to an on-disk key.

```bash
git commit -S -m "..."
git log --format='%h %G? %s' -1     # MUST print G — anything else, stop and diagnose
```

Verify the `G`. A commit that silently failed to sign will be rejected by branch
rulesets much later, after you have built more work on top of it.

**4 — Push.** Over **SSH**, never HTTPS, and **without `-u`**.

```bash
git push origin <task-slug>          # NOT -u
```

`-u` writes upstream tracking into `.git/config`, and the sandbox makes that file
unwritable — you get `error: could not lock config file .git/config`. The push
itself still succeeds; only the tracking write fails. Do not treat it as a failed
push, and do not try to clear the "stale lock" (see below).

HTTPS push returns `403 denied` by design — the tokens are `Contents: Read`, so
the SSH key is the only write path. If a remote is an `https://` URL, fix the
remote rather than reaching for a token.

**5 — Open the PR.** Explain *why*; the diff already shows what.

```bash
gh pr create --title "..." --body "..."
```

Body formatting is fragile in shell — see the `gh pr create` note in your global
instructions (plain double-quoted string, not a heredoc).

**6 — Test. Check `task --list` before running a tool bare.** A task carries the
env contract — `KEYCLOAK_ENV`, `BUILD_TAGS`, `TEST_TIMEOUT`, the `SOURCE_SECRETS`
sourcing — and invoking `go test` directly drops all of it silently. That is one
of the ways a suite reports `ok` having skipped everything.

```bash
task --list                         # the discovery surface; check it first
task test                           # unit tests, all services and packages
task lint                           # all services, packages and e2e
```

All tiers also run in-session as of 2026-08-04, and raw `go test` remains the
right tool for the case below:

```bash
go test ./...                       # ~96% of the suite
go test -tags=integration ./...     # works — needs the docker shim first
```

**Testing one service is the documented exception.** Every include in
`go-monorepo/Taskfile.yml` is `internal: true`, which makes those tasks
*unreachable* rather than merely unlisted — `task vaas:test` answers `Task
"vaas:test" is internal`, and `task --list` shows zero per-service tasks, even
though `services/vaas/Taskfile.yml` defines `test`, `test:unit`,
`test:integration` and `test:coverage`. So the choice is `task test` (everything)
or `go test ./services/vaas/...`, and the raw command is correct. The gap is in
the Taskfile.

Where a raw command recurs and **no** task covers it, add one rather than
normalising the bare invocation — a repeated raw command is a missing task with
extra steps, and the env contract it drops stays invisible until a run is green
for the wrong reason.

Container-backed tests used to be impossible here. They are not any more:
`allowAllUnixSockets` is on and the podman socket answers from inside the
sandbox. You still need a `docker` shim before anything pulls — it is in
[containers and the k8s tier](patterns/containers-and-k8s.md), along with what
that open socket costs. Read it before your first container command; skipping it
turns a five-minute setup into an hour of misattributed errors. The `ghcr.io`
mirrors are `internal`, and the shim is podman, so **your** process presents the
credential. Use `GHCR_TOKEN`; the two `GH_TOKEN_*` values are fine-grained PATs
and ghcr refuses them.

**7 — Comment on the issue or PR.** Report what actually happened, including
failures and skipped steps.

```bash
gh pr comment <n> --body "..."
gh issue comment <n> --body "..."
```

**7a — Tear down anything you brought up. Not optional, and not the human's
job.** If you created a kind cluster, a toolbox container, or images that existed
only for this run, destroy them once the tests are done *and* the PR or issue has
been updated — in that order, because review feedback often needs one more run
against the same cluster.

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
kind delete cluster --name <cluster>
podman rm -f <helper containers>
podman image prune -f && podman volume prune -f
free -m | head -2; df -h / | tail -1     # report what came back
```

This box has 4 GB of RAM and **~4.5 GB of swap** (a 496 MB partition plus a 4 GB
swapfile). A cluster left running held 1.6 GB of RAM and 8 GB of disk on
2026-08-04 — enough that the *next* session fails in ways that look nothing like
"someone forgot to clean up". Keep the gitignored artifacts the next run reuses
(`dev/kind/.kubeconfig`, `dev/caddy/certs/`, the mkcert CA), and name anything you
leave behind on purpose. Details and the keep/remove split:
[containers and the k8s tier](patterns/containers-and-k8s.md).

**Because swap exists, the box does not kill under memory pressure — it thrashes.**
That changes what a leftover cluster looks like from the next session's seat: not
an OOM kill but unbounded slowness, which is far harder to attribute. Measured
2026-08-09 with a warm cluster up: 393 MB available, and `/proc/pressure/memory`
at 147.9 s of cumulative *full* stall against 371.5 s for I/O, on 2 vCPU carrying
load 4.7. Two consequences worth knowing before you debug the wrong thing:

- **Do not diagnose a killed build as OOM without checking.** `dmesg` is closed
  (`kernel.dmesg_restrict=1`) and journald needs a group you are not in, but
  cgroup v2 keeps an unprivileged counter that is hierarchical and outlives the
  dead child cgroup: `grep oom_kill /sys/fs/cgroup/user.slice/memory.events`. It
  counts kills by **any** OOM killer, global included, so `0` is real evidence.
  A build that died with no `fatal error: out of memory` in its log and a zero
  counter was terminated by something else — a timeout, or you.
- **Do not add `--memory` to a podman build to "contain" it.** A cgroup limit
  converts today's slow build into a killed one, which is strictly worse. Cap
  concurrency instead (`go build -p 1`, `task --concurrency 1`); the linker is
  the real peak and `-p` will not shrink it.

Report the before/after numbers rather than the word "cleaned up" — a delete that
half-failed looks identical to one that worked until someone checks.

**7b — Optional: get an independent review from Codex.** Worth doing before you
ask a human to look, because self-review misses what you already believed.

```bash
~/.local/share/mise/shims/codex exec -s read-only \
    -C ~/src/<org>/<repo>-<task-slug> \
    --output-last-message /tmp/codex-<slug>.md \
    - < /tmp/codex-prompt-<slug>.md
```

Use the **shim path** — `mise activate` has not run in a non-interactive shell,
so plain `codex` is `command not found` unless you ran the `export PATH` line in
step 1. Prompt via stdin (`-`) to avoid shell escaping. `hook: Stop Failed` in the
output is a disabled plugin hook; benign.

This works in-session as of **2026-08-05**, and did not between 2026-08-03 and
then: `~/.codex/auth.json` was on the sandbox credentials deny list, so `codex`
died with `Permission denied (os error 13)`. If you see that today the box is
running stale settings — see the table below, and do not run `codex login`.

Tell Codex which checks are already green and ask it to focus on static analysis —
the Go build cache lives outside the workspace, so it cannot usefully run tests.
Ask it to judge your PR body's claims too, not just the diff; overclaiming is the
easiest thing to miss about your own work.

Then **judge the report** rather than applying it. Say which findings you accept,
which you think are wrong and why. A review you agree with unconditionally was not
worth requesting.

**8 — Review a PR.** Post the summary, every inline note and the verdict as a
**single** review via the REST reviews endpoint — `gh pr review --approve` cannot
anchor line comments. The exact recipe is in your global instructions under
"Reviewing a PR/branch". Inline comments only anchor to lines in the diff.

Approving, requesting changes, merging, and commenting on someone else's PR are
outward-facing. Get explicit go-ahead first.

**9 — Once the PR merges: tear down the worktree and re-sync.** A merged branch
that still has a worktree is how this box accumulates confusing state —
`git worktree list` grows, `main` reads as behind, and the next task branches off
something stale.

```bash
cd ~/src/<org>/<repo>
git worktree remove ../<repo>-<task-slug>    # --force only if you know what is dirty
git branch -d <task-slug>                    # -d, NOT -D
git fetch origin main && git merge --ff-only origin/main
git worktree prune
```

**`git branch -d` refusing is information, not an obstacle.** It means the branch
is not contained in `origin/main` — either the PR did not merge, or it merged as
a squash and the SHA differs. Check which before reaching for `-D`; the first case
means you are about to delete unmerged work.

The `fetch`/`merge` pair is usually redundant: `src-sync` runs hourly and
fast-forwards every repo that is on `main`, clean, and strictly behind. Run
`~/.local/bin/src-sync` yourself when you want it now, or when it reported a repo
as skipped.

## When something fails

Most devbox failures report the wrong cause. Match the symptom, do not trust it:

| symptom | actual cause |
|---|---|
| `error parsing config file: .mise.toml` | config is **untrusted**, not malformed → `mise trust` |
| `go: command not found`, `kubectl: command not found` | non-interactive shell; `mise activate` only runs from an interactive prompt → use `~/.local/share/mise/shims/<tool>` |
| `gh` says `please run gh auth login` | you invoked the **mise shim**. `gh` is the ONE tool that must NOT come from the shim → use `~/.local/bin/gh` |
| `Permission denied (publickey)` on push | ssh is not offering the key; `~/.ssh/config` must pin `IdentityFile ~/.ssh/devbox_agent` |
| `Couldn't find key in agent?` when signing | `user.signingkey` is in `key::` form, which needs an agent → use the **path** form |
| `gh` dies with `not a directory` | `~/.config/gh` is missing → `mkdir -p ~/.config/gh` |
| `403 denied` on push | HTTPS remote; tokens are read-only → use the SSH remote |
| container test cannot reach Docker | no `docker` binary and `XDG_RUNTIME_DIR` unset → install the shim in `patterns/containers-and-k8s.md`, do NOT set `DOCKER_HOST` |
| ghcr pull says `denied` | the shim IS podman, so **you** authenticate from auth files — read them in precedence order first. Use `GHCR_TOKEN` (classic `ghp_`); `GH_TOKEN_IDEN2` and `GH_TOKEN_PEZWARE` are fine-grained and carry no packages permission. `Login Succeeded!` proves nothing. See `patterns/containers-and-k8s.md` |
| `kubectl` cannot reach a kind cluster | loopback TCP is still blocked (separate from AF_UNIX) → drive the cluster from a toolbox container on the `kind` network, not by fixing the kubeconfig |
| `pnpm install` refuses a fresh version | the 7-day supply-chain cooldown, working as intended → add a dated `minimumReleaseAgeExclude` entry, never lower the floor |
| `Could not resolve to a Repository` | wrong token for that owner → run `gh` from inside the repo |
| `a branch named X already exists` right after a failed `worktree add` | the branch WAS created before the config write failed → retry with `--no-track`, or attach to it |
| `Couldn't find key in agent?` **only under `~/src/iden2/`** | the `includeIf gitdir:` work config overrides the global signingkey with the Mac's `key::` form → `git -c user.signingkey=~/.ssh/devbox_agent commit -S` |
| `could not lock config file .git/config` | **not** a stale lock — the sandbox masks it; the operation that needed it is unavailable, the rest of the command usually succeeded |
| `codex exec` dies with `Permission denied (os error 13)`, or `codex login status` reports `loggedIn: false` | stale settings on the box. `~/.codex/auth.json` was un-denied on 2026-08-05; the live `~/.claude/settings.json` still denies it → re-pull and merge the sandbox block. Do **not** run `codex login` — the file is on the host, it is masked from your session, and re-authenticating treats a visibility problem as a credential one |
| `git branch -d` says the branch is not fully merged, after the PR merged | the PR was **squash**-merged, so no commit with your SHA is in `main` → confirm on the PR page, then `-D` |

Full detail, with the mechanism behind each:
[devbox divergences](patterns/devbox-divergences.md).

## Do not

- **Do not** run `sign-push` for your own commits. It exists for the human to sign
  a batch; you sign as you go.
- **Do not** try to read `~/.claude/.credentials.json`. It is denied,
  deliberately, and nothing you are doing needs it. `~/.codex/auth.json` *is*
  readable — that is what makes step 7b work — but reach it through `codex`
  itself, never by opening the file.
- **Do not** treat the sandbox as containment for anything you hand to the
  container runtime. It runs outside the sandbox, so image pulls originate outside
  the proxied network path and bind mounts reach denied paths. Hostile code
  belongs on the disposable k8s node — see `~/src/public/0x58/linux/sandbox.md`.
- **Do not** leave a k8s node running. It bills hourly.
- **Do not** leave a local kind cluster or toolbox container running either. It
  bills in the next session's RAM instead of dollars, which is harder to trace.
  Tearing down is step 7a, and finishing without it is finishing the task badly.
