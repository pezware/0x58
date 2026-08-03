# Tailscale Nodes

Role-based Linode nodes on the tailnet. One shared Terraform module, one
dispatcher, three roles you can scale up and down independently.

```
dev/nodes/
├── ts-node                     # ./ts-node <role> <command>
├── modules/linode-node/        # instance + firewall + cloud-init + common.sh
└── roles/
    ├── devbox/                 # 4 GB, always on  — repos, agents, kubectl
    ├── k8s/                    # 4 GB, on demand  — docker + kind, disposable
    └── minimal/                # 1 GB             — exit node only, fall-back tier
```

Every node: **no inbound ports** (Cloud Firewall `DROP`, OpenSSH disabled),
Tailscale SSH as the only access path, secrets from Keychain into env for the
duration of one command.

## Relationship to `dev/exit-node/`

`dev/exit-node/` is **untouched and still authoritative** for the running
`pezware-cuatro`. It holds live tfstate; moving it would orphan that. The
`minimal` role here is its successor for *new* builds — if you ever build
`minimal`, destroy `pezware-cuatro` first or you will pay for both.

## Roles

| Role | Plan | Cost | Lifetime | Swap |
|---|---|---|---|---|
| `devbox` | g6-standard-2 · 4 GB | $24/mo | permanent | 4 GB — safe, never runs kubelet |
| `k8s` | g6-standard-4 · 8 GB | ~$0.072/hr (~$6.50 at 90 h) | per session | **0 — kubelet refuses to start with swap** |
| `minimal` | g6-nanode-1 · 1 GB | $5/mo | fall-back | 0 |

Typical steady state is `devbox` alone at $12/mo, plus `k8s` for the hours you
actually need a cluster.

## Setup

The `linode-pat` Keychain item already exists (see
[`../exit-node/linode/README.md`](../exit-node/linode/README.md)) and its scope —
Linodes R/W, Firewalls R/W — already covers these roles. What is new is one
**auth key per role**.

A Tailscale auth key grants *all* of its tags to whatever registers with it, so
one shared multi-tag key would make every box wear every tag and collapse the
ACL separation. Hence one key each:

| Role | Keychain item | Tag | Key kind |
|---|---|---|---|
| `devbox` | `tailscale-devbox-authkey` | `tag:devbox` | **single-use** |
| `k8s` | `tailscale-k8s-authkey` | `tag:k8s` | reusable |
| `minimal` | `tailscale-exit-authkey` *(existing)* | `tag:exit-node` | reusable |

**Single-use where you can, reusable only where you must.** The key is rendered
into instance `user_data`, so it lands in tfstate and in cloud-init's
`/var/lib/cloud` cache — `sensitive` only masks CLI output. A single-use key is
spent the moment the node joins, which makes the copy at rest worthless. That is
why `devbox`, built once and kept, uses one.

`k8s` stays reusable purely for ergonomics: it is destroyed and rebuilt
constantly, and minting a key per rebuild is friction you would route around.
It is therefore the higher-exposure key of the three — keep its expiry short.

**A single-use key is consumed on first join.** Rebuilding `devbox` after a
`destroy` needs a freshly minted key in the Keychain, or the node comes up
without a tailnet identity and is unreachable.

Generate at <https://login.tailscale.com/admin/settings/keys> with
**Pre-approved: ON · Tags: ON**, then:

```bash
security add-generic-password -U -s tailscale-devbox-authkey -a "$USER" -w
# paste tskey-auth-... at the prompt (never on the command line — shell history)
```

### ACL additions

Extend the policy at <https://login.tailscale.com/admin/acls/file>. The
`tag:exit-node` pieces already exist; add the two new tags and the traffic rules:

```jsonc
{
  "tagOwners": {
    "tag:exit-node": ["autogroup:admin"],
    "tag:devbox":    ["autogroup:admin"],
    "tag:k8s":       ["autogroup:admin"]
  },

  "acls": [
    // My own devices reach the work boxes.
    { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:devbox:*", "tag:k8s:*"] },

    // devbox reaches the cluster API. Deliberately NOT the reverse, and
    // deliberately nothing toward the MacBook Air — a compromised VPS gets no
    // path back to the laptop.
    { "action": "accept", "src": ["tag:devbox"], "dst": ["tag:k8s:6443,22"] }
  ],

  // Tag-owned devices reject SSH unless a rule says otherwise; without this,
  // `tailscale ssh` fails with a policy error that looks like a network problem.
  "ssh": [
    { "action": "check", "src": ["autogroup:member"],
      "dst": ["tag:devbox", "tag:k8s"], "users": ["arbeitandy", "root"] }
  ]
}
```

Defining `acls` replaces Tailscale's permissive default, so anything not listed
is denied — which is the point.

## Verify after apply

Check the node came up **tag-owned**. This is the failure that hides:

```bash
ssh arbeitandy@$(tailscale ip -4 pezware-devbox) 'tailscale status --json' \
  | python3 -c "import sys,json; s=json.load(sys.stdin)['Self']; print('Tags:', s.get('Tags'), '| KeyExpiry:', s.get('KeyExpiry'))"
```

Want `Tags: ['tag:devbox'] | KeyExpiry: None`.

If you see `Tags: None` and a real expiry roughly six months out, the node
registered **user-owned**. Everything appears to work — SSH included, because
`autogroup:self` covers a user-owned node — but every ACL rule written against
`tag:devbox` silently fails to match, and the node drops off the tailnet when
that key expires. `common.sh` now passes `--advertise-tags` explicitly so this
cannot depend on how the auth key was created, but create the key with the tag
as well.

## Daily use

```bash
./ts-node devbox apply       # one-time, ~5 min including the 0x58 restore
./ts-node devbox ssh
./ts-node devbox status

./ts-node k8s apply          # when you need a cluster (~4 min incl. node image)
./ts-node k8s destroy        # when you are done — ONLY this stops the billing

./ts-node <role> plan|start|stop|ip
```

### Attaching from a phone or tablet

`tmux` keeps the session alive; `mosh` survives the wifi-to-cellular handover
that kills plain SSH. `devbox` bootstrap creates a detached session named `main`
so the first connection from a phone has something to attach to:

```bash
mosh pezware-devbox -- tmux attach -t main
```

iOS: Tailscale + Blink Shell (native mosh). Android: Tailscale + Termux
(`pkg install mosh openssh`).

### Using the cluster from the devbox

`kind get kubeconfig` prints to stdout, which drops straight into the existing
`kubectl-context.bash` layout:

```bash
mkdir -p ~/.kube/configs/kind-dev
ssh pezware-k8s 'kind get kubeconfig --name dev' > ~/.kube/configs/kind-dev/config
kube-refresh && kube-use kind-dev
```

## Scaling back to minimal

```bash
./ts-node k8s destroy
./ts-node devbox destroy
./ts-node minimal apply          # $5/mo, exit node only
```

Set `advertise_exit_node = false` on `devbox` if you would rather keep exit-node
duty on a separate box; the default is `true`, which makes a standalone exit
node redundant while `devbox` is up.

## Gotchas

- **Powered-off Linodes still bill in full.** `stop` is a power switch, not a
  cost control. Only `destroy` stops charges — already documented in
  `../exit-node/README.md` and just as true here.
- **kind binds its API server to `127.0.0.1` by default**, so its kubeconfig is
  useless from another host and the serving cert has no SAN for the tailnet
  address. `roles/k8s/bootstrap.sh` sets `apiServerAddress` at creation time
  because it *cannot be retrofitted* — you would have to recreate the cluster.
- **kubelet will not start with swap enabled**, which is why `swap_mb` is 0 on
  `k8s` and 4096 on `devbox`. The split is the only reason both can be right.
- **Tag-owned devices reject SSH by default** — needs the explicit `ssh` ACL
  rule above, or `tailscale ssh` fails in a way that looks like a firewall.
- **cloud-init `runcmd` is once-per-INSTANCE, not once-per-boot.** The
  `scripts-user` module defaults to that frequency, so a reboot never re-runs
  it. Anything that must survive a reboot goes in `0x58-node-boot.service`,
  installed by `common_install_perboot_unit`, which re-runs the role script
  with `--per-boot`. That is why the devbox `tmux` session comes back.
- **The auth key is not tmpfs-only.** It is rendered into `user_data`, so it
  reaches tfstate and cloud-init's persistent cache. `/run` shredding limits the
  live copy, not the durable ones — hence the single-use preference above.
- **`templatefile()` cannot see `path.module`.** Sibling files must be read in
  the calling `.tf` and passed as vars — see `modules/linode-node/main.tf`.
- **Destroying a node leaves a stale machine** in the Tailscale admin console,
  and the next build appends `-1` to the hostname. Delete it after `destroy`.

## TODO

- [ ] Tailscale OAuth client instead of per-role auth keys (same TODO as `../exit-node/`)
- [ ] Optional Linode Volume on `devbox` so repos survive a rebuild

## Private agent instructions

`macos/dotfiles/claude/CLAUDE.md` in this repo is **sanitized**: the iden2-com
ticket runbook is stripped, because this repository is public and those project
and field IDs are employer-internal. `restore.sh` places that sanitized copy at
`~/.claude/CLAUDE.md` on Linux nodes, and symlinks `~/.codex/AGENTS.md` to it so
Codex and Claude read the same instructions.

The full version lives only on the Mac. Push it after a rebuild:

```bash
rsync -a ~/.claude/CLAUDE.md devbox:/home/arbeitandy/.claude/CLAUDE.md
```

The symlink means Codex picks the update up automatically — no second copy.

This is a deliberate trade: full reproducibility from git would mean publishing
the internal sections, so the node is reproducible up to a one-line sync. If you
skip it, the node still works; it just loses the ticket-creation runbook.

## Codex from Claude — the broker

Claude Code's bash is sandboxed: it cannot read `~/.codex/auth.json`, cannot
write `~/.codex`, and cannot reach OpenAI. A Codex spawned as a child of that
bash therefore dies before authenticating, failing to create its sqlite state.

[`linux/codex-broker`](../../linux/codex-broker) resolves that without weakening
the sandbox. Started outside it and as you, the broker holds the token and does
the work; Claude only speaks JSON-RPC to it over a unix socket. The grant is one
socket path, versus the three broad holes the alternative needed:

| | loosen sandbox | broker |
|---|---|---|
| read `~/.codex/auth.json` | yes | **no** |
| write `~/.codex` | yes | **no** |
| reach OpenAI hosts | yes | **no** |
| connect one fixed socket | no | yes |

One broker per workspace — `--cwd` is per-broker, so go-monorepo needs its own.

```bash
loginctl enable-linger arbeitandy          # once; see below
systemctl --user enable --now "codex-broker@$(systemd-escape ~/src/iden2/go-monorepo).service"
~/src/public/0x58/linux/codex-broker status
```

**Lingering is not optional.** Without it `systemd --user` tears down when your
last session ends, so the broker dies whenever you disconnect — which on a
headless box is most of the time.

Sockets live at `~//tmp/codex-broker/<slug>.sock` and are listed explicitly in
[`linux/claude-settings.json`](../../linux/claude-settings.json). A new workspace
needs its socket added there. The path is pinned deliberately: the plugin's own
brokers land in random `/tmp/cxc-XXXXXX/` directories, which cannot be
pre-declared in `allowUnixSockets`.

Confirm Claude is using it — `mode` must be `shared`, not `direct`:

```bash
CLAUDE_PLUGIN_DATA=~/.claude/plugins/data/codex-openai-codex \
  node ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs setup --json \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["sessionRuntime"])'
```

### This will break one day

`broker.json` is an internal plugin format written here by hand, so a plugin
update can invalidate it silently. The symptom is Codex reverting to
`mode: direct` and dying on the sqlite write — which looks like a sandbox problem
rather than a stale contract. Recovery is in CLAUDE.md under "Codex plugin broken
after a codex CLI upgrade": kill the broker and its app-server child, clear the
persisted state, re-run `codex-broker start`.

Never clean up with `pkill -f app-server-broker` — that pattern matches the shell
running the command and kills your own session. `codex-broker stop` kills by PID.

### Claude cannot reach the broker — use the relay

Tested and settled, so it does not get re-derived: **Claude Code's sandbox blocks
AF_UNIX at the syscall level.** From inside it, creating even its own socket in
`/tmp` — a path no allowlist governs — fails with `EPERM`. Since `connect()`
requires `socket()` first, every path-based exception is unreachable before it is
consulted. `allowUnixSockets` is set correctly and makes no difference.

The sandbox runs as PID 1 in its own PID namespace with outbound TCP brokered
through a SOCKS proxy; there is no equivalent shim for unix sockets. That also
explains why, from inside, `ss` sees none of the host's listeners and `kill -0`
reports live processes as dead — a limit of vantage point, not a fact about the
host. Verify anything about the host from outside it.

So the handoff is a **relay**, not a direct call:

```bash
# you, in your own shell (unsandboxed) — one line per handoff
node ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs \
  task --background "<prompt>"
```

Claude then reads the structured result itself from
`state/<slug>-<hash>/jobs/<id>.json` — no pasting output back.

The brokers still earn their keep: your invocation reaches them, so the companion
gets a warm shared runtime instead of a cold spawn.

**Rejected alternatives**, and why, so they are not retried:

- `excludedCommands: ["node"]` — matching is command-name based, so this exempts
  every node invocation, i.e. arbitrary JS outside the sandbox. Broader than the
  thing it was meant to avoid.
- `allowUnsandboxedCommands: true` — a common misreading. It does not enable
  `excludedCommands`; it lets the model use `dangerouslyDisableSandbox` on any
  command, removing the fail-closed guarantee entirely.
- Granting `~/.codex` writes, `auth.json` reads and OpenAI egress — three broad
  holes that put the OpenAI token inside the blast radius of anything Claude
  fetches from the web. The relay costs one command and grants nothing.

## Signing commits made on the devbox

All three repos enforce `required_signatures` via rulesets, so unsigned commits
cannot land on `main`.

`commit.gpgsign` is deliberately **off** on this box. Signing needs the forwarded
SSH agent, whose socket is AF_UNIX — refused at `socket()` inside Claude Code's
sandbox. With it on, every agent commit would fail hard rather than merely be
unsigned.

So agents commit unsigned and you sign the batch on the way out:

```bash
ssh -A devbox                      # -A is required; the agent IS the mechanism
cd ~/src/iden2/go-monorepo
~/src/public/0x58/linux/sign-push  # signs unsigned commits, verifies, pushes
```

One Touch ID tap per commit. Signing rewrites SHAs, so do it before anyone else
fetches the branch; `sign-push` uses `--force-with-lease` accordingly.

### Why not a devbox signing key

Considered and rejected. `~/.ssh` and `~/.gnupg` are in the sandbox's `denyRead`,
so an agent could not read a local key anyway — it would fail exactly as it does
now. Putting one somewhere readable would let any agent-run command exfiltrate
it, and `github.com` is in the egress allowlist. A stolen *signing* key lets
someone produce commits that appear verified as you, which is the one property
the Secure Enclave guarantees by construction: the key cannot be extracted, even
by you.

Leaving agent commits visibly unsigned until a human vouches for them is better
provenance than always-signing with a key that lives on a server.

### Identity split

Mirrors the Mac's attribution, inverted. Personal is the global default here;
`~/src/iden2/` includes `~/.config/git/work` for the work identity and key.
Both public keys are already in `allowed_signers`.

## Agent key escrow

The devbox signs with two keys, each registered to a different GitHub account —
and registration is manual, needing a browser session per account. So a rebuild
that generated fresh keys would end with two hand registrations every time, which
is what would make "rebuild in 10 minutes" untrue.

[`devbox-keys`](devbox-keys) escrows them in the macOS Keychain instead:

```bash
./dev/nodes/devbox-keys status     # what exists where
./dev/nodes/devbox-keys save       # escrow the current keys
./dev/nodes/devbox-keys restore    # reinstall onto a rebuilt devbox
```

`restore` rebuilds the public half from the private one, so fingerprints are
unchanged and existing GitHub registrations keep working. Verified by round-trip.

**Rebuild order:** `ts-node devbox apply` → `devbox-keys restore` → push CLAUDE.md
→ enable broker units. Only the last two are manual.

This does not widen exposure much — the private keys already sit unencrypted on
the devbox, which is the accepted trade for unattended agent signing. What it adds
is an encrypted backup of material that has none: `backup-devbox.sh` excludes
`.ssh/` deliberately, so today losing the devbox loses these keys.

The Secure Enclave keys are untouched and non-extractable; this script never sees
them.

## Where each role is driven from

| role | state lives | run it from | why |
|---|---|---|---|
| `devbox` | Mac | Mac | it cannot destroy itself mid-apply |
| `k8s` | devbox | devbox (so: phone) | the on-demand node you want without a laptop |
| `minimal` | Mac | Mac | fallback tier, rarely touched |

`ts-node` **refuses** the `k8s` role on macOS. Running it there would build a
second, independent state that knows nothing about a node the devbox already
created — terraform would then cheerfully make a duplicate, and neither state
could clean up the other. State divergence is silent and expensive; this refusal
is neither. Override with `TS_NODE_ALLOW_MAC_K8S=1` only if you know why.

### Secrets

Resolution order is environment → `~/.config/0x58/credentials.env` → macOS
Keychain. The first two are what let fleet ops run off the Mac; the Keychain
stays the source of truth where it exists.

On the devbox, put a **separate, narrowly-scoped** Linode PAT in that file —
Linodes + Volumes read/write, Events read-only, and nothing else. The Mac's token
is full-access, and an injected agent with it could delete the entire account.
The file is in the sandbox's `credentials.files` deny list, so agents cannot read
it; it exists for you, driving the fleet from a phone.

```bash
install -m 600 /dev/null ~/.config/0x58/credentials.env
cat > ~/.config/0x58/credentials.env <<'ENV'
LINODE_TOKEN=<scoped-pat>
TF_VAR_tailscale_auth_key=<reusable key tagged tag:k8s>
ENV
```

### Using the cluster from the devbox

```bash
ts-node k8s apply                    # ~4 min: node, kind, cluster
kube-setup-kind-remote               # defaults to pezware-k8s / cluster "dev"
kube-use kind-dev
kubectl get nodes
ts-node k8s destroy                  # only this stops the billing
```

`kube-setup-kind-remote` runs `kind get kubeconfig` **on the node** — kind and a
docker socket exist there, not on the devbox — and drops the result into the
existing `kubectl-context.bash` layout.

The kubeconfig already points at the node's tailnet address, because
`roles/k8s/bootstrap.sh` sets `apiServerAddress` at cluster-creation time. That
cannot be retrofitted: the API server bakes its SANs into the serving cert, so a
cluster created without it is unreachable from the devbox no matter what you edit
afterwards.

Requires two tailnet ACL rules, since the devbox is a *tagged device* and so is
not covered by `autogroup:member`:

```jsonc
"acls": [{ "action": "accept", "src": ["tag:devbox"], "dst": ["tag:k8s:6443,22"] }],
"ssh":  [{ "action": "accept", "src": ["tag:devbox"], "dst": ["tag:k8s"], "users": ["arbeitandy"] }]
```

Deliberately one-directional. Nothing grants k8s → devbox, so a throwaway cluster
node has no path to the box holding your source and credentials. Verified.
