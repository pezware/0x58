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

## Two deliberate trade-offs

**`git` is excluded from the sandbox.** Agent forwarding puts the SSH agent
socket at a random path (`/tmp/auth-agentNNNN/listener.sock`), which cannot be
pre-declared in `allowUnixSockets`. Rather than allow *all* Unix sockets, git
runs outside the sandbox.

This is less alarming than it sounds, and arguably stronger: git operations
authenticate through the **forwarded Secure Enclave key**, so every push and
every signature requires a physical Touch ID tap on the Mac. An injected agent
cannot push silently — it needs a human fingerprint. Hardware gating replaces
sandbox gating for exactly the command that has it.

**Codex hardening is a profile, not the shared config.**
`macos/dotfiles/codex/config.toml` is copied to both machines, and the Mac's
workflow passes `-s read-only` per invocation. Tightening the shared file would
change Mac behaviour as a side effect of hardening Linux. The devbox alias in
`bashrc` adds `-p devbox` on Linux only.

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

## What this does NOT protect against

- A compromised tailnet identity, or Linode control-plane compromise.
- Anything running **outside** an agent sandbox, including your own shell.
- `git`, by the deliberate exclusion above.
- Kernel or bubblewrap escape.
- Reading source. Every repo on the box is readable by design — the sandbox
  protects credentials and constrains egress, it does not make the source secret.

For genuinely hostile code, use the disposable k8s node or a throwaway VM. Do not
run it on the box holding all source and both subscription credentials.
