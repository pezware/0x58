# Tailscale Nodes

Role-based Linode nodes on the tailnet. One shared Terraform module, one
dispatcher, three roles you can scale up and down independently.

> **How this was built, and what each decision cost:**
> [devbox-build.md](devbox-build.md) — the security, sync, cost and feasibility
> trade-offs, including the ones that turned out to be wrong.

```
dev/nodes/
├── ts-node                     # ./ts-node <role> <command>
├── modules/linode-node/        # instance + firewall + cloud-init + common.sh
└── roles/
    ├── devbox/                 # 4 GB, always on  — repos, agents, kubectl
    ├── k8s/                    # 8 GB, on demand  — docker + kind, disposable
    ├── waltid/                 # 16 GB dedicated  — JDK + docker, build box
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
| `waltid` | g6-dedicated-8 · 16 GB | ~$0.216/hr (~$5.18/day) | per build campaign | 4 GB — no kubelet, so swap is a safety net |
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

./ts-node waltid apply       # a 16 GB build box (~6 min incl. the JDK)
./ts-node waltid destroy     # when the PRs are merged — ONLY this stops the billing

./ts-node <role> plan|start|stop|ip
```

### The waltid build box

The devbox has 2 vCPU and 4 GB, which a walt.id Gradle build exhausts — it was
sitting at load 28 with 3 GB in swap when this role was written. `waltid` is
where that build goes instead. It is a **remote builder**, not a second
workstation: no GitHub token, no agent session, no repo of its own. The agent
stays on the devbox and drives this box over Tailscale SSH.

```bash
./ts-node waltid apply                       # from the Mac
ssh pezware-waltid build-env                 # what the box has, with versions

# from the devbox — seed the repo, then build
rsync -a ~/src/iden2/waltid-identity-mirror/ waltid:~/src/waltid-identity-mirror/
ssh waltid 'cd ~/src/waltid-identity-mirror && ./gradlew build'
```

Three things about that handoff are not guessable, and each cost a step to find:

- **MagicDNS does not resolve from the devbox.** Every node here joins with
  `--accept-dns=false`, so `ssh pezware-waltid` fails with *"Name or service not
  known"* — which reads as a dead node rather than a naming one. Pin the tailnet
  IP in the devbox's `~/.ssh/config` and the readable name works everywhere.
- **Send the parent repo, not a worktree.** A worktree's `.git` is a *file*
  pointing into the parent's `.git/worktrees/`, so rsyncing the worktree alone
  lands a repo that no git command will touch. Push
  `waltid-identity-mirror/` and check the commit out on the far side;
  `git worktree prune` clears the stale metadata that comes with it.
- **`rsync`, not `git clone`.** The node holds no credentials, so it cannot
  reach a private repo on its own, and the ACL is one-directional so it cannot
  pull from the devbox either. That is the property being kept, not a limitation
  to work around — do not put a token here to make cloning work.

Measured on the first run: 107 MB in 7.4 s over the tailnet, and rsync is
incremental afterwards.

Long builds belong in the tmux session the bootstrap leaves ready, or they die
with the ssh connection: `ssh waltid -t tmux attach -t main`.

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
it, and egress from this box is unrestricted. A stolen *signing* key lets
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
| `waltid` | Mac | Mac | the devbox is its client, so it must not also be its owner |
| `minimal` | Mac | Mac | fallback tier, rarely touched |

`waltid` keeps its state on the Mac even though the devbox is what uses the
node. The devbox is already the box under pressure — it is why this role exists
— and giving it the power to destroy the machine its own agent is mid-build on
adds a failure the Mac does not have. Teardown is one command from here.

**Do not run one of these roles from a git worktree you then delete.**
`terraform.tfstate` is gitignored, so it lives beside `main.tf` and nowhere
else. Deleting the directory orphans a running Linode that nothing can now
destroy and that keeps billing — and `worktree-sweep --remove` deletes merged,
clean worktrees for a living. Move the state into the primary checkout before
the branch merges.

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

**Agents can read this file.** This paragraph claimed the opposite until
2026-08-04 — that it sits in the sandbox's `credentials.files` deny list — and
that stopped being true on 2026-08-03, when `c99f538` removed it so `gh` could
authenticate at all. The live deny list is the two OAuth token files, `~/.npmrc`,
`~/.config/gh/hosts.yml` and `~/.git-credentials`; `credentials.env` is not among
them. Scope every secret in here on the assumption that a session can print it.
That is why the Linode PAT is narrow and why `GHCR_TOKEN` is `read:packages` only.

```bash
install -m 600 /dev/null ~/.config/0x58/credentials.env
cat > ~/.config/0x58/credentials.env <<'ENV'
LINODE_TOKEN=<scoped-pat>
TF_VAR_tailscale_auth_key=<reusable key tagged tag:k8s>
GHCR_TOKEN=<classic PAT, read:packages ONLY>
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

## GitHub tokens on the devbox

Agents drive the whole issue → worktree → commit → PR → CI-status loop, so they
use a GitHub token, so the token has to be the thing that's safe.

> **Correction (2026-08-03).** This section previously claimed `gh` escapes the
> sandbox via `excludedCommands`, and could therefore read a credentials file that
> agents cannot. That is **false**. It was asserted from the setting being present
> rather than from running it.
>
> Measured inside a real session: `excludedCommands` does *not* exempt a command
> from `credentials.files` or `denyRead`. `gh` failed with
> `credentials.env: Permission denied`, and `git commit -S` with
> `Couldn't load public key`. Agents could not open a PR at all.
>
> Access is now granted **explicitly** instead — `credentials.env` removed from the
> credentials deny list, `~/.ssh` removed from `denyRead`. What that costs, and
> what stays closed, is in
> [autonomy and its limits](../../macos/dotfiles/claude/skills/devbox-workflow/patterns/autonomy-and-limits.md).

Two **fine-grained** PATs, because a fine-grained PAT has exactly one resource
owner and `gh` holds one credential per host:

| token | owner | repos | expires |
|---|---|---|---|
| `gh-pat-devbox-pezware` | pezware | all | 2027-08-03 |
| `gh-pat-devbox-iden2` | iden2-com | 9 of 51, listed below | 2026-11-01 |

Both: Metadata R · **Contents R** · Issues RW · Pull requests RW · Actions R.

**`Contents: Read` is the point.** Without write, a token holder cannot push over
HTTPS — verified, GitHub returns `403 Permission denied` — so every push must go
through the SSH signing key. The token can open PRs and read CI; it cannot put
code anywhere.

**A repo outside the token's list answers `404`, not `403`.** GitHub hides a
private repo rather than admit it exists, so `gh` reports *"Could not resolve to
a Repository"* — which reads as a deleted or misspelled repo, not as a missing
grant. Measured 2026-08-20, the iden2 token selects nine: `demos`,
`documentation-website`, `external-documentation`, `go-monorepo`,
`iden2-roadmap`, `infra-tf`, `platform-apis`, `restful-api-guidelines`,
`spec-kit`. The other 42 in the org answer 404 by design. Widen the list in the
token's own settings — the token value does not change, so nothing on the box
needs an edit and no session needs a restart.

[`gh-token-wrapper`](../../linux/gh-token-wrapper) is installed as
`~/.local/bin/gh` (ahead of the mise shim) and picks the token from the
repository's owner. It reads that owner from three places, in order: an explicit
`--repo`/`-R`, then the arguments the command already carries (`gh api
/repos/OWNER/…`, `gh api /orgs/OWNER/…`, `gh repo <verb> OWNER/REPO`), then the
origin remote. A packages endpoint takes `GHCR_TOKEN` instead, whatever the
owner. [`gh-token-wrapper-test`](../../linux/gh-token-wrapper-test) covers each
source, and the shapes that must select nothing. The wrapper reads
`~/.config/0x58/credentials.env`, which agents can also read — that is now the
deliberate arrangement rather than an asymmetry we were relying on.

Honest limit: agents can read the tokens, and `gh auth token` prints whichever is
selected. Scoping is what bounds the damage, and it is doing all of the work here
— a leaked token reads code the agent already had and can open PRs or comments.
It cannot put code anywhere, because that needs `Contents: Write`.

`~/.config/gh` must exist as a directory. The sandbox masks `hosts.yml` inside it,
and masking a file under a missing parent leaves the parent as a *file*, after
which every `gh` call dies with `not a directory` — which reads like a corrupt
install rather than a sandbox artifact.

The classic `repo`-scoped token has been removed from `~/.config/gh/hosts.yml`.
Keep it that way — `repo` grants push over HTTPS and would silently bypass the
signing-key gate.

### Gotcha: mise config trust

`mise` refuses untrusted `.mise.toml`, and reports it as *"error parsing config
file"* with the real reason on the following line. An untrusted repo therefore
breaks **every** mise-provided tool there, not just one. `mise trust <path>` fixes
it; a fresh clone or a rebuild needs it again.

## Rebuilding the devbox

`user_data` changes force instance replacement, so applying config drift *is* a
rebuild. That is safe by design — `~/src` lives on a detachable volume, and the
instance is cattle — but the root disk is gone, and with it everything that was
never captured in this repo.

```bash
./dev/nodes/backup-devbox.sh snapshot     # 1. source lives on the volume, but be sure
./dev/nodes/ts-node devbox apply          # 2. destroys and recreates the instance
#    3. delete the OLD node in the Tailscale admin console  <-- do not skip
./dev/nodes/devbox-keys restore           # 4. SSH keys back from Keychain escrow
#    5. re-place ~/.config/0x58/credentials.env (below)
#    6. re-do the ghcr login (below) <-- root disk is gone, so auth.json is too
./dev/nodes/devbox-smoketest              # 7. prove the loop actually works
```

**Step 3 is not optional.** Tailscale will not reuse a hostname while a stale
record holds it, so the new node joins as `pezware-devbox-1`. The box is then
perfectly healthy and completely unreachable by the name every script uses.
`devbox-smoketest` checks for the suffix explicitly.

**Step 5** has no automated path, because the file holds five secrets that
deliberately never enter this repo or a backup:

```bash
kc() { security find-generic-password -s "$1" -a "$USER" -w; }
{ printf 'GH_TOKEN_PEZWARE=%s\n'          "$(kc gh-pat-devbox-pezware)"
  printf 'GH_TOKEN_IDEN2=%s\n'            "$(kc gh-pat-devbox-iden2)"
  printf 'LINODE_TOKEN=%s\n'              "$(kc linode-pat-devbox)"
  printf 'TF_VAR_tailscale_auth_key=%s\n' "$(kc tailscale-devbox-authkey)"
  printf 'GHCR_TOKEN=%s\n'                "$(kc ghcr-pat-devbox)"
} | ssh devbox 'umask 077; mkdir -p ~/.config/0x58 && cat > ~/.config/0x58/credentials.env'
```

**Step 6** is separate from step 5 on purpose. Putting `GHCR_TOKEN` in the file
is not the same as being logged in: the thing that pulls is the podman *service*,
which reads its own `~/.config/containers/auth.json`, and that file lives on the
root disk a rebuild destroys. Miss this and every ghcr pull 403s while the token
sits correctly in place — which reads as a scope problem and is not one.

```bash
ssh devbox 'umask 077; bash -lc "
  set -a; . ~/.config/0x58/credentials.env; set +a
  mkdir -p ~/.config/containers
  printf %s \"\$GHCR_TOKEN\" | podman login ghcr.io -u arbeitandy --password-stdin \
    --authfile ~/.config/containers/auth.json"'

# prove it, from the Mac — expect: arbeitandy
ssh devbox 'bash -lc "podman login --get-login ghcr.io"'
```

Why an explicit `--authfile`: podman's default is
`$XDG_RUNTIME_DIR/containers/auth.json`, and `XDG_RUNTIME_DIR` is **unset** in
every non-interactive and agent shell on this box (the same gotcha that breaks
the socket probe). `~/.config/containers/auth.json` is deterministic and survives
a reboot; a runtime-dir login does not survive either.

Piped over stdin on purpose — a value passed as an argument would be visible in
`ps` on the way through.

Then `claude login` and `codex login`, which are interactive OAuth and cannot be
scripted. `restore.sh` runs automatically from cloud-init and handles the rest:
dotfiles, packages, the gh wrapper, podman, lingering, mise trust, and pointing
`user.signingkey` at the on-disk key.

### What the 2026-08-03 rehearsal found

The box came back with source, dotfiles, podman and the gh wrapper all present —
and could not sign a commit as the right account. Nothing looked broken. The
lesson is that presence is not function, which is why `devbox-smoketest` makes a
real signed commit, requests a real token, and opens a real socket rather than
inspecting configuration.

| gap | why it was invisible |
|---|---|
| signing key was the Mac's `key::` form | file present and well-formed; `key::` names an **agent-held** key, and the devbox has no agent — fails with *"Couldn't find key in agent?"* whichever key it names |
| lingering lost | lives on the root disk; user units die at logout, so it only breaks when nobody is attached |
| mise trust lost | reported as *"error parsing config file"*, which blames TOML syntax; breaks every mise tool in the repo at once |
| stale tailnet record | new node silently renamed, box healthy but unreachable by name |
