# Where the devbox differs from the Mac

Every entry here caused a real failure whose error message pointed somewhere else.
That is the common thread: **the symptom names the wrong subsystem.**

## Signing: `key::` versus a path

```
user.signingkey = key::ssh-ed25519 AAAA…    → error: Couldn't find key in agent?
user.signingkey = /home/…/.ssh/devbox_agent → %G? = G
```

`key::<pubkey>` names a key held by an **agent**. That is correct on the Mac,
where Secretive keeps the key in the Secure Enclave and there is no file to point
at. The devbox is the mirror image — a key on disk, no agent — so it needs a
**path**.

The Mac's gitconfig therefore cannot work here whatever key it names. If you ever
see `Couldn't find key in agent?`, do not hunt for a missing agent; check the
*form* of `user.signingkey`.

Worse than failing: the Mac's value names a key belonging to a **different GitHub
account**, so a success would be silently misattributed.

## Two identities, and how GitHub resolves them

GitHub resolves a signature by **commit email → account → that account's signing
keys**. The email decides the identity; the key only has to belong to it.

| key | account | role |
|---|---|---|
| `devbox_agent` | `arbeitandy` | auth **and** signing |
| `devbox_agent_personal` | `achtungandy` | signing only — SSH auth with it fails, correctly |

Two keys exist because GitHub enforces key uniqueness across accounts; the same
key cannot be registered twice.

## `allowed_signers` is local-only

It governs `git log --show-signature` and nothing else. GitHub never consults it.

But `sign-push` refuses to push unless `%G?` reports `G`, so a correct signing key
with a stale signers file still blocks the workflow — a failure that looks like a
signing problem and is really a verification-config problem.

## ssh offers only default identity names

`devbox_agent` is not `id_ed25519`, so ssh never offers it and GitHub answers
`Permission denied (publickey)` while the key is present, valid and registered.
`~/.ssh/config` pins it:

```
Host github.com
    User git
    IdentityFile ~/.ssh/devbox_agent
    IdentitiesOnly yes
```

Signing does **not** need this — it reads the file directly. Only auth does. So
"signing works but push fails" is a coherent state, not a contradiction.

## mise: trust, and non-interactive shells

**Trust.** mise reports an untrusted config as `error parsing config file`, with
the real reason on the *next* line. The headline blames TOML syntax for what is a
trust prompt, and it breaks **every** mise tool in that repo at once, not one. A
fresh clone or worktree needs `mise trust`.

**PATH.** `mise activate` rewires PATH from an *interactive prompt hook*. In a
non-interactive shell — which includes most scripted invocations — no mise tool is
on PATH, and `go: command not found` is a lie about a working install. Use the
shim directly:

```bash
~/.local/share/mise/shims/go test ./...
```

`mise which <tool>` is **context-sensitive**: it reads the current directory's
`.mise.toml`, so it answers differently in different repos. Never use it to locate
a binary for a script.

## gh needs its config directory to exist

The sandbox masks `~/.config/gh/hosts.yml`. Masking a file under a **missing**
parent leaves the parent as a *file*, after which every `gh` call dies with
`not a directory` — which reads like a corrupt install. `mkdir -p ~/.config/gh`.

`gh` also selects its token from the origin remote's owner, so it must be run
**inside a repo**. Outside one it has no token.

## No Homebrew

apt owns the base system; mise owns every dev tool. Do not install dev tooling
with apt — it shadows mise's shims with older builds and makes upgrades ambiguous.
The exceptions are deliberate and documented in `linux/packages.txt`.

## Egress is allowlisted

Package registries and source hosts only. A network failure to an arbitrary host
is the sandbox working, not a broken box. Do not route around it.

## `.git/config` is unwritable, and the lock is not stale

```
error: could not lock config file .git/config
warning: update of config-file failed
```

`.git/config.lock` is a **character device** (`1, 3` — i.e. `/dev/null`) owned by
`nobody:nogroup`, bind-mounted there by the sandbox. It does not exist outside a
session. Claude Code ships `allowGitConfig = false` by default, and blocking the
*lock* is how it stops git writing the config at all — git will not write without
first acquiring the lock.

This is a sandbox-escape defence, not debris. Git config is executable surface:
`core.pager`, `core.hooksPath` and aliases all run commands, so an agent that can
write it can run arbitrary code on the next innocuous `git` invocation.

**Never delete it.** `rm`-ing a root-owned device node from another party's repo
internals is not a call to make, and it will simply reappear.

What breaks, and what does not:

| fails | still works |
|---|---|
| `git push -u` (the tracking write only) | `git push` |
| `git remote add` / `set-url` | `git fetch`, `git pull` |
| `git config --local ...` | `git commit`, including `-S` |
| branch-config cleanup on `branch -D` | `git checkout`, `git branch` |

The pattern to recognise: the *command* reports an error while its *primary
effect* succeeded. Check the actual result — `git ls-remote`, `git log` — before
concluding anything failed.
