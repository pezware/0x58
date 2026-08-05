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

| where you are | commit email | account | signing key |
|---|---|---|---|
| everywhere by default, incl. `~/src/public/` | `andy@pezware.com` | `achtungandy` | **`devbox_agent_personal`** |
| `~/src/iden2/` (via `includeIf`) | `andy@iden2.com` | `arbeitandy` | **`devbox_agent`** |

| key | account | role |
|---|---|---|
| `devbox_agent` | `arbeitandy` | auth **and** signing |
| `devbox_agent_personal` | `achtungandy` | signing only — SSH auth with it fails, correctly |

Two keys exist because GitHub enforces key uniqueness across accounts; the same
key cannot be registered twice. **All pushes authenticate as `arbeitandy`** via
`devbox_agent`, in both trees — auth and signing are independent, and only signing
has to match the email.

### The failure this pairing prevents

Crossing them is silent in every place you would look. Until 2026-08-04
`restore.sh` set the global `user.signingkey` to `devbox_agent`, so every commit
in `~/src/public/` was signed with the **work** account's key while committing as
`andy@pezware.com`:

| signal | said |
|---|---|
| `git push` | succeeded |
| `git log %G?` | `G` |
| `devbox-smoketest` | all signing checks green |
| GitHub, on the PR | **`unknown_key`** |

`%G?` agreed because `allowed_signers` had been cross-mapped — it listed
`devbox_agent` under *both* addresses, so local verification was configured to
accept exactly the thing GitHub rejects. An over-permissive signers file does not
merely fail to catch this; it manufactures the confidence that hides it.

If a commit lands unverified, do **not** re-register keys. Check the pairing:

```bash
git config --get user.email        # which identity am I?
git config --get user.signingkey   # does that account own this key?
```

`devbox-smoketest` now asserts the pairing against GitHub's public
`users/<login>/ssh_signing_keys` endpoint, which is the only authority that
matters and needs no token.

## `allowed_signers` is local-only

It governs `git log --show-signature` and nothing else. GitHub never consults it.

But `sign-push` refuses to push unless `%G?` reports `G`, so a correct signing key
with a stale signers file still blocks the workflow — a failure that looks like a
signing problem and is really a verification-config problem.

The reverse is the dangerous direction, and it is the one that bit: a signers file
that is too *permissive* makes `%G?` report `G` for a signature GitHub will
reject. Map each key to the one address whose account owns it, never to both.
`G` means "this box can verify it", not "GitHub will".

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

## The work include overrides the global signing key

Signing works everywhere **except** `~/src/iden2/`, where it fails with
`Couldn't find key in agent?`.

`~/.config/git/work` is pulled in by `includeIf gitdir:~/src/iden2/`, and **an
include overrides the global**. The tracked work file carries the Mac's `key::`
value, so the global path form set for this box never reaches iden2 repos. Same
key, same email — only the *form* differs, which is why it looks like a key
problem and is really a config-precedence problem.

`restore.sh` re-points it on Linux. If you meet it on a box that has not been
restored since, override per-commit rather than editing global config (which the
sandbox blocks anyway):

```bash
git -c user.signingkey=~/.ssh/devbox_agent commit -S -m "..."
```

The devbox key is already in `allowed_signers` under `andy@iden2.com`, so local
verification resolves and GitHub attributes the commit to `arbeitandy`.

Found by an agent taking a real ticket. The smoke test missed it because it signs
in a throwaway repo under `/tmp`, which never matches the `gitdir:` condition — a
reminder that a test in an artificial location can only prove artificial things.
