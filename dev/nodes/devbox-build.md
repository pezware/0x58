# Building the devbox

How a dead ThinkPad became a remote workstation that AI agents can drive, and
what each decision cost.

This is the reasoning, not the runbook. For "how do I rebuild it", see
[README.md](README.md); for the sandbox specifically,
[linux/sandbox.md](../../linux/sandbox.md).

The goal was narrow at first — get an old laptop useful again — and ended up
somewhere else: a box that can be destroyed and rebuilt on demand, reached from a
phone, and handed to an agent that can take a ticket through to a pull request
without the Mac being involved at all.

---

## Step 0 — the pivot, and why it mattered

The original plan was Debian on a ThinkPad. It failed for a reason worth
recording: **the keyboard had dead keys — `l` and `k` among them.** Not a subtle
failure. You cannot type `ls`, or a login name containing an `l`, or `k`ubectl.

The lesson generalised: *a machine you cannot reliably reach is not a server.*
Every later decision leaned on remote access being the primary interface rather
than a convenience, which is why Tailscale came before almost everything else.

What survived the pivot was the package philosophy: **apt owns the base system,
mise owns every dev tool.** No Homebrew on Linux. The split matters because it
keeps one cross-platform `config.toml` authoritative for toolchains on both Mac
and Linux, so a rebuilt box gets the same Go, kubectl and terraform as the
laptop, from the same file.

---

## Step 1 — shape and cost

Three roles, one Terraform module. The question was whether to run one big box or
split by lifetime.

| role | type | specs | price | lifetime |
|---|---|---|---|---|
| `devbox` | `g6-standard-2` | 2 vCPU / 4 GB / 80 GB | **$24/mo** | always on |
| `k8s` | `g6-standard-4` | 4 vCPU / 8 GB / 160 GB | $48/mo — **$0.072/hr** | on demand |
| `minimal` | `g6-nanode-1` | 1 vCPU / 1 GB / 25 GB | $5/mo | optional exit node |
| volume | block storage | 50 GB | **$5/mo** | outlives every instance |

*(Prices from Linode's public API, us-east, at time of writing.)*

**Always-on cost is $29/mo** — the devbox plus its volume. The k8s node is the
interesting part: at $0.072/hour, a full day of cluster work costs about $1.73.
Running it permanently would cost $48/mo to sit idle.

The trade was deliberate. A single `g6-standard-4` would be simpler and always
ready, at ~$53/mo all-in. Splitting saves roughly **$45/mo** in exchange for a
`terraform apply` wait whenever a cluster is needed. That wait is a real cost
when you want a cluster *now*, and the reason the split still wins is that
wanting one is rare — a few times a month.

The 4 GB tier was not the first choice. A 2 GB node is $12/mo and was genuinely
tempting, but agents are memory-hungry: a language server, a Go build and two
agent sessions will exhaust 2 GB and start swapping, and a swapping box feels
broken in a way that is hard to attribute. **$12/mo to never think about it.**

Swap itself is role-dependent and enforced in code: 4 GB on the devbox,
**0 on k8s**, with a `lifecycle.precondition` that refuses to build a k8s node
with swap enabled. kubelet fails to start when swap is on unless explicitly
configured, and discovering that after a cluster half-builds is miserable.

---

## Step 2 — access, and the decision everything else inherited

**No public listener. OpenSSH is disabled entirely.** Access is Tailscale SSH
over the tailnet, plus a Linode Cloud Firewall.

This closes off inbound risk almost completely, and it is the single highest
leverage decision here — no fail2ban, no key rotation panic, no exposure to
internet-wide scanning. It also constrained everything downstream in ways that
were not obvious at the time:

- **Tailscale SSH does not honour `SendEnv`/`AcceptEnv`.** `ssh -o SetEnv=…` was
  tested and silently does nothing. That killed the tidiest option for getting a
  GitHub token onto the box per-connection, and pushed us toward a credentials
  file (Step 6).
- **Forwarded agent sockets land at a random path** —
  `/tmp/auth-agentNNNN/listener.sock`, a new one per connection. This looks like
  trivia. It later became the reason agents cannot be given container access
  (Step 7), because a random path in a writable directory cannot be masked.

Two ACL mistakes are worth recording because both *looked* fine:

- **A tagged device is not `autogroup:member`.** Rules granting members access to
  the k8s node did not apply to the devbox, because the devbox is tag-owned. The
  devbox was denied while the ACL appeared to allow it.
- **A leftover `allow all` rule silently negated the isolation.** Everything
  worked, which was the problem. Removing it and re-testing proved k8s→devbox is
  actually blocked.

Nodes are **tag-owned** (`tag:devbox`) rather than user-owned, which means no key
expiry and no reauthentication prompts on a headless box — a user-owned node
would go offline every 180 days.

**The MagicDNS name is the real interface.** Every script says `devbox`, not an
IP. That makes a stale tailnet record a genuine outage: Tailscale will not reuse
a hostname while an old record holds it, so a rebuilt node joins as
`pezware-devbox-1` and every script breaks against a perfectly healthy box.
Deleting the old node is a mandatory rebuild step, and the smoke test checks for
the suffix.

---

## Step 3 — provisioning, and three bugs that reported success

Terraform, one role-based module, `prevent_destroy` on the volume.

Three failures shared a shape: **they reported success while being broken.**

**`user_data` has a hard 16 KB limit.** The k8s role hit it at 17,249 bytes. On
inspection, the devbox was **66 bytes from the same cliff** — meaning the rebuild
path was already broken and nobody knew, because rebuilds had not been tested.
Fixed with `base64gzip()`; cloud-init detects gzip by magic bytes, so nothing
else changed.

**`runcmd` runs once per *instance*, not per boot.** Anything needed after a
reboot must be a systemd unit. Obvious in hindsight; invisible until a reboot.

**`KillMode=control-group` killed the tmux session the unit created.** The
per-boot unit started a session, systemd considered the oneshot finished, and
tore down its whole cgroup — taking the session with it. The unit logged
`Result=success` while destroying its own output. `KillMode=process` plus
`RemainAfterExit=yes` fixed it. A related trap: the unit is *regenerated from
`common.sh` on every run*, so editing it on the box does nothing.

**Terraform state is the real host dependency.** It lives on the Mac. Losing it
does not destroy the box, but it does mean no more `apply` — the definition and
the reality come apart. Anyone hardening this further should move state to
object storage before worrying about almost anything else on this page.

---

## Step 4 — what survives, and what is allowed to die

The design that makes rebuilds cheap:

```
sdb  50 GB  →  /home/arbeitandy/src     Linode Volume — persists
sdc  80 GB  →  /                        instance disk — discarded on rebuild
```

**Instance is cattle, volume is pet.** `user_data` changes force replacement, so
applying config drift *is* a rebuild. `~/src` detaches and reattaches; 223 MB of
source came back untouched.

The sharp edge is what lives on the root disk. It is easy to assume "the box was
restored" because source and dotfiles are present. The rebuild proved otherwise:
**lingering** (`/var/lib/systemd/linger`) and **mise trust state** both live on
the root disk, both were lost, and both fail in ways that do not look like the
cause. Lingering only breaks once nobody is attached; mise reports an untrusted
config as `error parsing config file`, blaming TOML syntax.

Sync is deliberately split by *what a thing is*:

| what | where it lives | why |
|---|---|---|
| source | volume + git remotes | already replicated; git is the backup |
| dotfiles, settings, skills | this repo | version-controlled, reviewable |
| SSH keys, PATs | **macOS Keychain escrow** | secret; must never enter a public repo or a backup |
| agent memory | snapshots only | written on the box, exists nowhere else |
| OAuth credentials | nowhere | re-issued by logging in; cheaper than protecting them |

Backups exclude secrets **on purpose** — `SECRET_EXCLUDES` drops `.ssh/`,
`.credentials.json`, `*.pem`, `terraform.tfstate*`. A backup you must protect as
carefully as the box defeats the point. Secrets go to the Keychain instead, where
`devbox-keys restore` regenerates public keys from the private half so **GitHub
registrations stay valid across rebuilds** — no re-registering keys.

Two hard-won details: `lost+found` is root-owned and made rsync exit 23, marking
*every* snapshot INCOMPLETE until excluded; and exit 24 (vanished files) is
tolerated while everything else is fatal, because a live box always has files
disappearing mid-sync.

**A restore you have never run is a hypothesis.** That is what Step 8 is about.

---

## Step 5 — identity, and a gotcha with real teeth

Commits are signed with SSH keys. Two GitHub accounts are involved
(`arbeitandy`, `achtungandy`), and **GitHub enforces key uniqueness across
accounts** — the same key cannot be registered twice, so the box needs two keys.

The subtle failure: a commit was attributed to the *wrong account*. GitHub
resolves a signature by **commit email → account → that account's signing keys**.
The email decides the identity; the key only has to belong to it.

Then the deepest gotcha of the whole build, found only by rebuilding:

```
user.signingkey = key::ssh-ed25519 AAAA…    → error: Couldn't find key in agent?
user.signingkey = /home/…/.ssh/devbox_agent → %G? = G
```

**`key::<pubkey>` names a key held by an *agent*.** That is correct on the Mac,
where Secretive keeps the key in the Secure Enclave and there is no file to point
at. The devbox is the mirror image — a key on disk, no agent — so it needs a
**path**. The Mac's gitconfig cannot work on the devbox no matter which key it
names, and `restore.sh` was copying it verbatim.

Worse than failing: the copied value named a key belonging to the *other* GitHub
account, so a success would have been silently misattributed.

Also worth separating, because they are independent mechanisms: **`allowed_signers`
governs local verification only.** GitHub does not consult it. But `sign-push`
refuses to push unless `git log %G?` reports `G`, so a correct signing key with a
stale signers file still blocks the workflow.

`sign-push` itself rebases onto the **merge-base**, not `origin/main`. Using the
remote head would quietly rebase the branch onto newer upstream work as a side
effect of signing it — surprising behaviour from a command called `sign-push`.

---

## Step 6 — tokens, after ruling out the alternatives

Agents need the GitHub API: open PRs, read CI, comment on issues. The box
therefore needs a token, and the box is the least trusted thing here.

We researched what people actually do for `gh` auth on remote hosts, and rejected
the appealing options for concrete reasons:

- **Forwarding a credential helper over a socket** — the mechanism VS Code Remote
  uses. Blocked: Tailscale SSH's environment restrictions plus long-lived tmux
  sessions mean per-connection state goes stale in existing panes.
- **Short-lived GitHub App tokens** — genuinely better, but needs an App, an
  installation, and a refresh daemon. Real work for a single-user box.
- **A relay back to the Mac** — defeats the goal. The point is that the Mac can be
  closed, upgraded, or lost.

So: **a token on disk, made as boring as possible.** Two fine-grained PATs,
because a fine-grained PAT has exactly one resource owner and `gh` holds one
credential per host — no single token can cover both `pezware/*` and
`iden2-com/*`.

**Both are `Contents: Read`, and that is the load-bearing choice.** Without write,
a token holder cannot push over HTTPS. Verified rather than assumed:

```
remote: Permission to pezware/0x58.git denied to arbeitandy.
fatal: unable to access 'https://github.com/pezware/0x58.git/': 403
```

Every push must therefore go through the SSH signing key. An agent can open a PR
and read CI; it cannot put code anywhere.

The wrapper selecting the token works because of an **asymmetry the sandbox
creates**: `gh` is in `excludedCommands`, so it runs *outside* the sandbox and can
read a credentials file that sandboxed commands cannot. Same trick as `git` and
the signing key — the tool is trusted with a credential, the agent driving it is
not.

**Honest limit:** `gh auth token` prints whichever token is selected. A determined
agent can extract one. Scoping bounds the damage; secrecy does not. The wrapper is
a scope selector, not a vault — and the classic `repo`-scoped token it replaced
has been removed, because `repo` grants HTTPS push and would bypass the gate
entirely.

---

## Step 7 — the sandbox, and the one switch we refused

The threat model is specific. Tailscale handles intrusion. What it cannot handle
is **prompt injection persuading an agent already running on the box** to read a
credential and send it somewhere — and Linode's `outbound_policy` is `ACCEPT`, so
nothing at the network layer stops that. Egress control inside the sandbox does.

Configured to **fail closed**: `failIfUnavailable: true` and
`allowUnsandboxedCommands: false`. By default Claude Code warns and continues
unsandboxed when bubblewrap is missing, which converts a broken sandbox into no
sandbox. This is also why `bubblewrap` and `socat` are required packages — without
them Claude Code refuses to start, which is the intent.

The interesting constraint, discovered while trying to give agents container
access for `testcontainers`:

**On Linux, Unix-socket blocking is all-or-nothing.** From the shipped schema:
`allowUnixSockets` is *"macOS only … Ignored on Linux (seccomp cannot filter by
path)."* The mechanism explains it — seccomp filters on register values, but
`connect()`'s path sits behind a userspace pointer, and dereferencing it in-kernel
is a TOCTOU hazard. macOS Seatbelt resolves paths and can allow one socket; Linux
gets `allowAllUnixSockets`, or nothing.

And "all" includes the forwarded SSH agent from Step 2 — at a *random path in
`/tmp`*, which cannot be masked. Enabling it would let an agent sign commits and
push over SSH, walking around the `Contents: Read` gate from Step 6 and destroying
the property that a signature means a person authorised it.

We measured the cost before deciding, and it is small:

| | count |
|---|---|
| test files needing containers | **28** |
| total test files | **746** |
| already behind `//go:build e2e`/`integration` | yes |

A plain `go test ./...` skips them. Agents run ~96% of the suite sandboxed;
container tiers belong to a human or to CI. Podman is installed and works — it is
simply not reachable from inside a sandbox, verified with a probe that is blocked
inside (`exit 7`) and returns `200` outside.

What the sandbox explicitly does **not** protect against: a compromised tailnet
identity, anything running outside a sandbox including your own shell, `git` and
`gh` by deliberate exclusion, kernel or bubblewrap escape, and reading source —
every repo on the box is readable by design.

---

## Step 8 — proving it, which is the only step that counts

Everything above was *believed* to work. On 2026-08-03 we destroyed the instance
and rebuilt it.

It came back with source, dotfiles, podman and the gh wrapper all present — and
**could not sign a commit as the right GitHub account.** Nothing looked broken.
Every file was where it belonged.

Six gaps, each invisible to inspection:

| gap | why it hid |
|---|---|
| signing key was the Mac's `key::` form | file present and well-formed; needs an agent that does not exist here |
| lingering lost | root disk; user units die at logout — only breaks when unattended |
| mise trust lost | reported as `error parsing config file`; breaks every mise tool at once |
| stale tailnet record | node silently renamed; healthy box, unreachable by name |
| claude not installed | native installer was a manual step nobody had re-run |
| skills/commands missing | a missing skill is not an error — the agent just never offers it |

The through-line: **every one was a file that was present, or a step that
reported success.** `cloud-init status` said `done`. 58 mise tools installed. The
volume reattached cleanly.

Hence [`devbox-smoketest`](devbox-smoketest), which checks by **doing** — it makes
a real signed commit, requests a real token, opens a real socket. And every check
has a **negative control** where one exists, because a test that only proves the
happy path cannot distinguish *working* from *absent*. The token check that
matters is not "the right token works"; it is **"the wrong token is refused"**.

Current state: **30 passed, 0 failed.**

---

## Where it landed

```
$29/mo   always-on devbox + volume
~$2/mo   k8s node, at typical use
─────
~$31/mo  for a machine that survives its own destruction
```

Against a MacBook that no longer has to be open, reachable from a phone over
mosh, with agents that can take work to a pull request on their own.

**Still manual on rebuild** (both documented in [README.md](README.md)): deleting
the old tailnet node, and re-placing `credentials.env` from the Keychain. Plus
`claude login` / `codex login`, which are interactive OAuth by design.

**Known gaps, honestly:** Terraform state is Mac-local and single-copy.
`~/.claude/agents` is not captured by `inventory.sh`, so it has no restore path.
Per-project agent memory was lost in the rebuild — it is in snapshots now, but
that came too late for the first one. And the token limit from Step 6 stands: an
agent can read the token it is allowed to use.

The recurring lesson, stated once: **things believed to work were broken until
actually run** — the rebuild path, the per-boot session, the backup markers, the
ACLs, the signing key. Every one was found by executing it, and none by reading
it.
