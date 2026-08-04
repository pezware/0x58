# Agent sandboxing on the devbox

Applied by `restore.sh` on Linux only:
[`claude-settings.json`](claude-settings.json) and
[`codex-devbox.config.toml`](codex-devbox.config.toml).

## The threat this addresses

Tailscale and the Linode Cloud Firewall handle *inbound* risk well — the box has
no public listener and OpenSSH is disabled. That is not the exposure that
matters here.

The devbox holds, in plaintext on disk:

- `~/.claude/.credentials.json` — Claude subscription OAuth, mode 0600
- `~/.codex/auth.json` — ChatGPT subscription OAuth

Both contain **refresh tokens**, which mint new access tokens indefinitely until
revoked. Linux has no Keychain equivalent, so this is an accepted exception
rather than a solved problem.

The realistic attack is therefore not someone reaching the box. It is **prompt
injection persuading an agent already running on it** to read one of those files
and send it somewhere — and the Linode firewall's `outbound_policy` is `ACCEPT`,
so it will not stop that. Egress control inside the sandbox is what does.

## What is configured

**Fail closed.** `failIfUnavailable: true` and `allowUnsandboxedCommands: false`.
By default Claude Code *warns and continues unsandboxed* when bubblewrap is
missing; that default converts a broken sandbox into no sandbox. This is also why
`bubblewrap` and `socat` are in [`packages.txt`](packages.txt) as required rather
than optional — without them Claude Code refuses to start, which is the intent.

**Credentials hidden.** `sandbox.credentials` (Claude Code 2.1.187+) denies reads
of both token files, `~/.npmrc`, `~/.config/gh/hosts.yml`, and unsets
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GH_TOKEN`, `LINODE_TOKEN`, and
`TF_VAR_tailscale_auth_key` for sandboxed commands.

**Filesystem.** Reads denied for `~/.ssh`, `~/.gnupg`, `~/.config/gcloud`,
`~/.kube`, `~/.aws`, and the Tailscale state directories. Writes limited to
`~/src` and `/tmp`.

**Egress allowlisted.** Package registries and source hosts only. Codex goes
further with `network_access = false`; it escalates to a human when a command
needs the network.

## Three deliberate trade-offs

**Agents can sign, push and use `gh`.** As of 2026-08-03 this is granted
*explicitly*: `~/.ssh` was removed from `denyRead`, and
`~/.config/0x58/credentials.env` from the credentials deny list.

It had to be explicit, because `excludedCommands` does **not** do what we assumed.
`git` and `gh` are both listed there and both were still subject to the deny
lists — measured inside a real session, `gh` failed with
`credentials.env: Permission denied` and `git commit -S` with
`Couldn't load public key`. **Listing a command does not exempt it from
`credentials.files` or `denyRead`.**

The cost is real and stated plainly: a signature no longer proves a *person*
authorised the commit — it proves this box produced it. Prompt injection here can
push signed code to any repository the key reaches, which rotating a token does
not undo.

What did **not** move: `~/.claude/.credentials.json` and `~/.codex/auth.json` stay
denied (verified — reads return `Permission denied`), `~/.ssh` stays in
`denyWrite`, and AF_UNIX stays blocked. That last one is why the forwarded
**Secure Enclave** agent remains unreachable even though its socket symlink sits
in a now-readable directory: seccomp blocks the syscall, not the path. The Mac's
key is still the Mac's.

A caution for anyone probing this: `test -r` on a denied file returns *success*.
`access(2)` is not intercepted — only the actual read is.

Worth being precise, because it constrains every later decision: on Linux
`allowUnixSockets` is not merely impractical here, it is **inert**. Its own
schema reads *"macOS only: Unix socket paths to allow. Ignored on Linux (seccomp
cannot filter by path)."* Blocking is a seccomp filter on `socket()`, and seccomp
sees register values, not the path behind the `connect()` pointer — dereferencing
that in-kernel would be a TOCTOU hazard. macOS Seatbelt resolves paths, so it can
allow one socket; Linux gets exactly one switch, `allowAllUnixSockets`, and it is
all-or-nothing. Any future "just allow this one socket" on this box is not a
config change, it is a decision to allow every socket including the SSH agent.

This paragraph used to claim that git operations authenticate through the
**forwarded Secure Enclave key**, so every push and signature needed a Touch ID
tap and an injected agent could not push silently. **That was already false when
it was written.** The same 2026-08-03 change that let agents sign and push set
`user.signingkey` to an on-disk *path* (`~/.ssh/devbox_agent`) and pinned
`IdentityFile` to the same key for github.com. Verify rather than trust it:

```bash
git config --get user.signingkey          # a path ⇒ signs with no agent, no tap
grep -A1 'Host github.com' ~/.ssh/config  # IdentityFile ⇒ pushes with no tap
```

The devbox has been signing and pushing unattended ever since — that is the
documented success of the loop, not a regression. The lesson is the one this repo
keeps relearning: a security property described in prose decays silently, while
the same claim written as a probe fails loudly.

**Codex hardening is a profile, not the shared config.**
`macos/dotfiles/codex/config.toml` is copied to both machines, and the Mac's
workflow passes `-s read-only` per invocation. Tightening the shared file would
change Mac behaviour as a side effect of hardening Linux. The devbox alias in
`bashrc` adds `-p devbox` on Linux only.

**Container tests now run inside agents (2026-08-04).** `allowAllUnixSockets` is
on, so rootless podman's Docker-compatible socket answers from a sandboxed Bash
call and agents run the `integration` and `e2e` tiers themselves.

The reason this was refused for so long — that agents would reach the forwarded
SSH agent and push without a Touch ID tap — did not survive contact with the
config above: they were already pushing with an on-disk key. What the switch
actually costs is different, and larger:

**The container runtime executes outside the sandbox, so anything delegated to it
escapes both controls.** Measured, not inferred:

| delegated through podman | sandbox control it bypasses |
|---|---|
| `docker pull docker.io/library/alpine:3.20` succeeded in-session | egress allowlist (`docker.io` is not in `allowedDomains`) |
| `-v $HOME:/m` reads paths a direct `cat` cannot | `filesystem.denyRead` |

The egress allowlist is named above as the one thing that stops an injected agent
exfiltrating a refresh token, since the Linode firewall's `outbound_policy` is
`ACCEPT`. A reachable container runtime routes around it. The credential
deny-list still blocks a *direct* read — both token files return
`Permission denied`, and `~/.codex/auth.json` was added to
`sandbox.credentials.files` on 2026-08-04 after it turned out to be listed only
under `denyWrite` while this document claimed it was denied outright.

So the honest statement of the posture is: the sandbox constrains the agent's own
syscalls, and stops being a containment boundary the moment work is handed to the
runtime. Hostile code belongs on the disposable k8s node, as it always did.

The trade is cheap, which is why it is easy to hold: **28 of 746** test files in
the go monorepo need containers, and they already sit behind `//go:build e2e` or
`integration` tags that a plain `go test ./...` skips. Agents run the other ~96%
sandboxed; container tiers belong to you or to CI, like `sign-push`.

## Verify it is actually on

Configuration that silently does nothing is worse than none, because it creates
false confidence. Check rather than assume:

```bash
command -v bwrap socat                     # both must exist
claude --version                           # needs >= 2.1.187 for sandbox.credentials
python3 -m json.tool ~/.claude/settings.json >/dev/null && echo "settings parse OK"
ls ~/.codex/devbox.config.toml
```

Then, inside a Claude session on the devbox, confirm a sandboxed command cannot
read the token file — it should fail, not print contents:

```
cat ~/.claude/.credentials.json
```

And confirm egress is filtered — an allowlisted host should work while an
arbitrary one should not:

```
curl -sS -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org
curl -sS -o /dev/null -w '%{http_code}\n' https://example.com
```

And confirm the container socket is reachable — this expectation **inverted** on
2026-08-04. Run it in both places: a blocked socket and an absent one look
identical from inside, so the control run is what makes the result mean anything.

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  --unix-socket "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock" http://d/_ping
```

Both outside and inside a Claude session this must print `200`. If it fails
inside, `allowAllUnixSockets` has been lost and the container tiers are stranded.

Keep the `${XDG_RUNTIME_DIR:-...}` fallback. That variable is **unset** in a
non-interactive shell and inside an agent session, so the bare form resolves to
`/podman/podman.sock` and fails with curl exit 7 — indistinguishable from the
sandbox blocking it. That false negative cost real time on 2026-08-04; the
fallback is the whole reason this probe is trustworthy.

## What this does NOT protect against

- A compromised tailnet identity, or Linode control-plane compromise.
- Anything running **outside** an agent sandbox, including your own shell.
- `git`, by the deliberate exclusion above.
- Kernel or bubblewrap escape.
- Reading source. Every repo on the box is readable by design — the sandbox
  protects credentials and constrains egress, it does not make the source secret.

For genuinely hostile code, use the disposable k8s node or a throwaway VM. Do not
run it on the box holding all source and both subscription credentials.
