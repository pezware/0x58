# Autonomy, and what it does not include

The devbox agent can complete the whole loop unattended: sign commits, push, open
PRs, comment. That was a deliberate posture change on 2026-08-03, chosen with the
trade stated explicitly.

**What it gave up:** a signature no longer proves a person authorised the commit.
It proves the devbox produced it. Anything that can inject a prompt into a session
here can push signed code to any repository the key reaches, and rotating a token
does not undo that.

Knowing this is the point. It means the honest description of your signature is
"this box made this commit", and you should not describe it to anyone as human
review having happened.

## What is still closed, and why it stays closed

| still denied | why |
|---|---|
| `~/.claude/.credentials.json` | OAuth **refresh** tokens — mint new access tokens indefinitely until revoked |
| `~/.codex/auth.json` | same |
| `~/.config/gh/hosts.yml` | a classic `repo`-scoped token here would grant HTTPS push and bypass the read-only gate |
| writing to `~/.ssh` | you may read the keys; replacing them is not part of any task |
| AF_UNIX sockets | keeps the forwarded **Secure Enclave** agent unreachable |

The last one is worth understanding, because it is the one boundary that did not
move. `~/.ssh/agent.sock` points at the Mac's Secure Enclave key. It stays out of
reach because seccomp blocks the syscall, not because of file permissions — so
unmasking the directory did not expose it. The Mac's key is still the Mac's.

`test -r` on a denied file returns success: `access(2)` is not intercepted, only
the actual read is. Do not use a permission probe to decide whether a file is
reachable — it will tell you the wrong thing.

## Tokens

Two fine-grained PATs, selected automatically by the origin remote's owner:

| owner | scope |
|---|---|
| `pezware` | all repos |
| `iden2-com` | `go-monorepo`, `platform-apis` only |

Both are **Metadata R · Contents R · Issues RW · Pull requests RW · Actions R**.

`Contents: Read` is load-bearing. You cannot push with a token; HTTPS push returns
`403`. Every push goes through the SSH key. If you find yourself wanting a token
with write access, the answer is no — use the SSH remote.

You *can* read the tokens. Bounded on purpose: a leaked one reads code you already
had and can open PRs or comments. It cannot put code anywhere.

## Outward-facing actions

Signing and pushing to your own branch is ordinary work. These are not, and need
explicit go-ahead:

- approving or requesting changes on a PR
- merging anything
- commenting on someone else's PR or issue
- creating issues in `iden2-com` (they carry mandatory project metadata — see your
  global instructions)
- `terraform apply` / `destroy` on any node

The test: would a human be surprised to discover you did it on their behalf?
