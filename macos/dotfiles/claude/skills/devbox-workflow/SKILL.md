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

**1 — Read the issue.** `gh` picks its token from the origin remote's owner, so
run it **inside the repo**. Outside a repo it has no token and fails confusingly.

```bash
cd ~/src/<org>/<repo>
~/.local/bin/gh issue view <n> --json title,body,labels,milestone
```

**`gh` is the one tool that must not come from the mise shim.** `~/.local/bin/gh`
is the wrapper that selects the token; `~/.local/share/mise/shims/gh` is raw gh
with no credential at all, and answers `please run gh auth login`. The
"use the shim" advice below applies to `go`, `kubectl` and friends — never to `gh`.
An interactive shell resolves plain `gh` correctly because `~/.local/bin` precedes
the shims on PATH; a non-interactive one may not.

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

**6 — Test.** All tiers run in-session as of 2026-08-04:

```bash
go test ./...                       # ~96% of the suite
go test -tags=integration ./...     # works — needs the docker shim first
```

Container-backed tests used to be impossible here. They are not any more:
`allowAllUnixSockets` is on and the podman socket answers from inside the
sandbox. You still need a `docker` shim and a ghcr login before anything pulls —
both are in [containers and the k8s tier](patterns/containers-and-k8s.md), along
with what that open socket costs. Read it before your first container command;
skipping it turns a five-minute setup into an hour of misattributed errors.

**7 — Comment on the issue or PR.** Report what actually happened, including
failures and skipped steps.

```bash
gh pr comment <n> --body "..."
gh issue comment <n> --body "..."
```

**7b — Optional: get an independent review from Codex.** Worth doing before you
ask a human to look, because self-review misses what you already believed.

```bash
~/.local/share/mise/shims/codex exec -s read-only \
    -C ~/src/<org>/<repo>-<task-slug> \
    --output-last-message /tmp/codex-<slug>.md \
    - < /tmp/codex-prompt-<slug>.md
```

Use the **shim path** — `mise activate` has not run in a non-interactive shell,
so plain `codex` is `command not found`. Prompt via stdin (`-`) to avoid shell
escaping. `hook: Stop Failed` in the output is a disabled plugin hook; benign.

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
| image pull fails or is rate-limited | not logged in to ghcr → `gh auth token \| podman login ghcr.io -u arbeitandy --password-stdin`, from inside the repo |
| `Could not resolve to a Repository` | wrong token for that owner → run `gh` from inside the repo |
| `a branch named X already exists` right after a failed `worktree add` | the branch WAS created before the config write failed → retry with `--no-track`, or attach to it |
| `Couldn't find key in agent?` **only under `~/src/iden2/`** | the `includeIf gitdir:` work config overrides the global signingkey with the Mac's `key::` form → `git -c user.signingkey=~/.ssh/devbox_agent commit -S` |
| `could not lock config file .git/config` | **not** a stale lock — the sandbox masks it; the operation that needed it is unavailable, the rest of the command usually succeeded |

Full detail, with the mechanism behind each:
[devbox divergences](patterns/devbox-divergences.md).

## Do not

- **Do not** run `sign-push` for your own commits. It exists for the human to sign
  a batch; you sign as you go.
- **Do not** try to read `~/.claude/.credentials.json` or `~/.codex/auth.json`.
  They are denied, deliberately, and nothing you are doing needs them.
- **Do not** treat the sandbox as containment for anything you hand to the
  container runtime. It runs outside the sandbox, so image pulls ignore the egress
  allowlist and bind mounts reach denied paths. Hostile code belongs on the
  disposable k8s node — see `~/src/public/0x58/linux/sandbox.md`.
- **Do not** leave a k8s node running. It bills hourly.
