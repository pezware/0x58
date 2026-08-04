# Confinement design — closing the container bypass

**Status: design, not posture.** Nothing here is implemented.
[`sandbox.md`](sandbox.md) remains the posture of record and describes what is
actually running. This document proposes what to build next and, just as
importantly, records what was measured on 2026-08-04 so the next session argues
with evidence rather than with prose.

## The goal, and the tension inside it

> A comfortable environment for Claude Code and Codex to run development and
> testing end to end, restricted from anything else.

Those two halves fight each other, and it is worth saying how before choosing
tools. "End to end" on this box means kind clusters, image pulls, container
networking and bind mounts. That capability set *is* the bypass described in
`sandbox.md`: the runtime executes outside the agent sandbox, so pulls ignore the
egress allowlist and mounts ignore `denyRead`.

So no amount of tightening the *agent's* sandbox helps. The agent is not doing
anything the sandbox can see — it is asking a privileged-enough helper to do it.
Every option below is therefore about constraining the helper, not the agent.

## What is measured true (2026-08-04)

Probed on the live box, because two properties documented in prose had already
decayed silently and the same class of decay is the actual risk.

| probe | result | consequence |
|---|---|---|
| `/proc/sys/net/ipv4/ip_unprivileged_port_start` | `1024` | compose tier still blocked; Caddy cannot bind 80/443 |
| `swapon --show` | 496 MB partition + 4 GB swapfile, **swapfile 0 B used** | box is not under memory pressure; zram would spend RAM to fix nothing |
| `podman info` AppArmor | `false`, `rootless=true` | **rootless podman applies no AppArmor profile** — `CAP_MAC_ADMIN` is unavailable in the initial userns. Containers are seccomp-only. |
| host AppArmor | enabled, 109 profiles | the host MAC layer exists but does not extend to the agent's containers |
| `/dev/tpm*`, `systemd-analyze has-tpm2` | absent / `partial` (`-firmware -driver`) | **no TPM on this Linode** — TPM-sealed credentials are off the table |
| `podman run -v <root-owned 0600>` | `Permission denied` | a rootless container **cannot** read root-owned files |
| same, user-owned 0600 (negative control) | contents printed | proves the above is about ownership, not a broken mount |
| container `id` | `uid=0(root)` | container-root is counterfeit — it maps to `arbeitandy` on the host |
| `sudo -n id` **inside a Claude session** | exit 1: `no new privileges` **and** `/etc/sudo.conf is owned by uid 65534` | in-sandbox escalation is blocked twice over |
| `wc -c < ~/.claude/.credentials.json`, same session (liveness control) | `Permission denied` | proves the sandbox was actually engaged for the above |
| `/run/podman/podman.sock`; system `podman.socket` | absent; `inactive` | **no rootful socket** — the agent cannot request a privileged runtime |
| `touch ~/.0x58-write-probe` in-session | exit 0 | **`allowWrite` is `~`, not `~/src`** |
| `touch ~/.ssh/...` (negative control) | `EROFS: Read-only file system` | denial is a read-only remount, **not `EACCES`** |

The middle group is the foundation of everything below. Without the negative
control the container result would have been unfalsifiable: a blocked read and a
broken mount look identical from inside.

**The last two are the most serious finding of the session, and they contradict
this repo's own documentation.** `sandbox.md` states "Writes limited to `~/src`
and `/tmp`." The live setting is `allowWrite: ["~", "/tmp"]` with a `denyWrite`
list that does **not** include `~/.bashrc`, `~/.profile`, `~/.config/systemd/user`,
`~/.local/bin`, or `~/.claude/settings.local.json`. Combined with
`arbeitandy ALL=(ALL) NOPASSWD:ALL`, that is a working escalation path:

> An injected agent cannot become root itself — `no_new_privs` stops it, measured.
> It does not need to. It writes a shell profile, a systemd user unit, or a
> `settings.local.json` hook, and waits for **you** to log in. Your session is
> unsandboxed and holds passwordless root.

Note that `~/.claude/settings.json` is denied while `settings.local.json` is not,
and that planting agent hooks is exactly the persistence technique used by the
2026-08-04 npm worm in [`supply-chain-triage.md`](supply-chain-triage.md).

An operational aside worth keeping: the denial surfaced as `EROFS`, not `EACCES`.
The sandbox masks paths by remounting read-only rather than through Unix
permissions, so any tooling that branches on `errno == EACCES` will misclassify
this boundary.

## Why not SELinux

Two independent reasons, either of which is sufficient.

**It is unavailable where it would have to act.** Debian trixie ships no usable
SELinux policy, `/sys/fs/selinux` does not exist on this box, and rootless podman
cannot apply MAC labels for the same `CAP_MAC_ADMIN` reason that leaves AppArmor
at `false`. Standing up SELinux here means relabelling the entire filesystem and
maintaining a policy Debian barely carries — against a runtime that cannot use it.

**It is the wrong layer even if it worked.** The bind mount is *requested by the
agent* and honoured by podman running as the agent's own uid. A policy that lets
`arbeitandy` read `$HOME` — and it must, it is their home — cannot distinguish
`cat ~/.claude/.credentials.json` from `-v $HOME:/m`. Both are the same uid
reading the same inode through the same permissions. This is an **authorization**
question at the podman API, not a **labelling** question at the filesystem.

SELinux is overloading *and* ineffective. Drop it.

## Why mitmproxy — but not in the mode you are picturing

The egress hole is real and the agent sandbox structurally cannot close it: the
allowlist is enforced on the agent's own syscalls, and the container's syscalls
are not the agent's. A proxy is the right shape of answer. The mode matters far
more than the tool.

**Do not intercept TLS.** Full interception decrypts every request body and puts
the plaintext in one process — including the OAuth refresh tokens this whole
design exists to protect. That concentrates the crown jewels into a new,
network-facing target in order to defend them. It also breaks certificate-pinned
clients and requires distributing a CA into every container, where a failure is
indistinguishable from a block.

**Do filter on SNI, without decrypting.** Reading the `ClientHello` server name
and then allowing or dropping gives the allowlist and a per-hostname audit log,
with no plaintext custody at any point. In mitmproxy this is a short addon on the
`tls_clienthello` hook that calls `data.context.fail()` for unlisted names. The
boring alternative is a plain forward proxy (squid, tinyproxy) with a `CONNECT`
allowlist — no interception, hostname logs, and far more operational history.
Either is acceptable; the non-decrypting *mode* is the requirement.

**A proxy nobody is forced to use is decoration.** `HTTP_PROXY` is opt-in, and an
injected agent simply would not set it. Enforcement has to come from the network
layer: an nftables `output` chain that DROPs by default and ACCEPTs only DNS plus
traffic to the proxy's port. Policy lives in the proxy; enforcement lives in
nftables. Neither substitutes for the other.

The honest limit: a container started with `--network=host` inherits the host's
netns and, depending on how the nftables rules are keyed, may sidestep them. That
is not a reason to skip this — it is a reason the socket proxy below is the
partner control, not an alternative to it.

## The control that does the most work: principal separation

Cross-checked with Codex this session, which pushed back usefully on an earlier
draft that proposed only a single `runner` uid. Its objection — that moving podman
to another uid is cosmetic while the agent's own uid holds passwordless root — was
**correct in conclusion and wrong in mechanism**, and the difference matters.

Codex asserted injected code could "simply become root, or launch rootful podman."
Both were measured shut: `sudo` fails in-sandbox under `no_new_privs`, and there is
no rootful socket. The path that is actually open is the profile-write above. So
the objection stands, but the thing to fix first is the **write scope**, not sudo.

The design follows from one line of reasoning:

- The agent **must** be able to read its own token, or it cannot authenticate.
- Therefore any process running as the agent's uid can read it.
- A container the agent starts runs as the agent's uid.
- ⇒ File permissions alone **cannot** both authenticate the agent and deny its
  containers the token. That is not a configuration gap; it is arithmetic.

What that argument does **not** say is that nothing helps. It says one credential
cannot be hidden from its own client. Every *other* secret on the box is still
protectable, and today a single injected agent reaches all of them.

**Split the principals.** Four accounts instead of one:

| uid | holds | runs |
|---|---|---|
| `arbeitandy` | sudo, signing key, Linode + GitHub tokens | human administration only — **never an agent** |
| `claude-agent` | only Claude's own OAuth token | Claude Code |
| `codex-agent` | only Codex's own OAuth token | Codex |
| `runner` | nothing | rootless podman, owns the socket |

The honest claim: this **cannot** protect Claude's refresh token from a compromise
of Claude itself. It **does** stop Claude injection reaching Codex's token, the
GitHub token, the Linode token, the signing key, or your sudo. That is most of the
blast radius, and today all of it sits behind one uid.

Two implementation notes, both from Codex and both easy to get wrong:

- **Remove the local podman engine from the agent uids entirely**, leaving only
  `podman-remote` (Debian packages it as a remote-only binary, and it is already
  in `packages.txt`). Merely *configuring* a remote default is not enforcement —
  an agent can select local mode and start its own engine.
- **Bind mounts resolve on the runner's side**, so `runner` cannot mount an agent
  home even if asked. Shared work must live somewhere deliberate — `/srv/workspaces`
  rather than any agent's `~`. Expect container-created files to be runner-owned;
  plan for a shared group with setgid directories.

### Concrete plan for the runner uid

Written out because "give podman its own uid" hides three problems that only
appear when you try it. Measured prerequisites first:

| fact | value | consequence |
|---|---|---|
| `/home/arbeitandy` | `drwx------` (0700) | **`runner` cannot traverse into it at all** — it cannot reach `~/src` |
| `arbeitandy` subuid | `100000:65536` | `runner`'s range must not overlap → start at `200000` |
| `/run/user/<uid>` | `0700`, systemd-managed | the default podman socket is unreachable across uids |

The first is the one that bites. Do **not** solve it by relaxing `~` to 0750 —
that weakens the exact boundary this is meant to build. Bind-mount instead, which
moves no data because `~/src` is already the `/dev/sdb` volume:

```bash
# 1. The account. No sudo, no password, shell only because systemd --user wants one.
sudo useradd -m -s /bin/bash runner
sudo usermod -aG runner arbeitandy          # so the agent can reach the socket

# 2. Subuid range that does NOT overlap arbeitandy's 100000:65536.
echo 'runner:200000:65536' | sudo tee -a /etc/subuid /etc/subgid

# 3. The user manager must survive logout, or the socket dies with the session.
sudo loginctl enable-linger runner

# 4. Workspace reachable by BOTH uids without opening ~ .
sudo mkdir -p /srv/workspaces
sudo mount --bind /home/arbeitandy/src /srv/workspaces
echo '/home/arbeitandy/src /srv/workspaces none bind,nofail 0 0' | sudo tee -a /etc/fstab

# 5. Socket on a shared path — /run/user/<runner> is 0700 and unreachable.
#    A drop-in overriding podman.socket's ListenStream, with group access.
sudo -u runner mkdir -p ~runner/.config/systemd/user/podman.socket.d
# ListenStream=/srv/podman/runner.sock  SocketMode=0660  SocketGroup=runner
sudo -u runner XDG_RUNTIME_DIR=/run/user/$(id -u runner) systemctl --user enable --now podman.socket
```

**What breaks — expect all of these, none are surprises after the fact:**

- **Images, volumes, networks and build cache are per-user.** `runner` starts
  empty; the toolbox image must be rebuilt under it. Budget one rebuild, not a
  migration.
- **Bind mounts resolve on the runner's side**, so `-v $HOME/src:...` silently
  refers to *runner's* home. Every path becomes `/srv/workspaces/...`.
- **Container-created files come back owned by `runner`**, not you. Needs a shared
  group with setgid directories, or you will be chowning after every run.
- **`DOCKER_HOST` and the podman shim both change** to the new socket path. The
  shim in the devbox-workflow skill hardcodes
  `unix:///run/user/1000/podman/podman.sock` and must be updated in the same
  change, or every cluster command breaks at once.
- **kind clusters are per-socket.** An existing cluster under `arbeitandy` is
  invisible to `runner` — tear it down before cutting over, not after.

**Verification, with the control that makes it mean anything.** The whole claim is
that a runner-owned container cannot read the agent's credentials:

```bash
# Expect: Permission denied. This is the point of the exercise.
podman --remote --url unix:///srv/podman/runner.sock run --rm \
  -v /home/arbeitandy:/m:ro alpine:3.20 cat /m/.claude/.credentials.json

# CONTROL — expect success. Without it, the failure above could just be a bad mount.
podman --remote --url unix:///srv/podman/runner.sock run --rm \
  -v /srv/workspaces:/m:ro alpine:3.20 ls /m
```

Note the second command is also the acceptance test for the bind mount: if the
workspace is unreachable the runner is useless, and that failure looks identical
to the success we want on the first command.

**Then filter what the API will accept.** A socket proxy rejecting
`HostConfig.Binds` outside an allowlist and refusing `Privileged`, `--network=host`
and `--pid=host`. This is the layer where "which mount is legitimate" is decidable,
which is precisely what MAC could not do. Anyone holding a podman socket has code
execution as its owner — acceptable here only because `runner` is credential-free
by construction.

## On the Debian keychain question

Asked directly this session: is there a macOS Keychain equivalent on Debian?

**No true equivalent, and the reason is structural rather than a missing package.**
Keychain's boundary is a per-application ACL enforced against the code signature,
backed for some items by the Secure Enclave. Linux has no userspace analogue to
the first part. Every mainstream secret store — libsecret/gnome-keyring, KWallet,
`pass`, the kernel keyring — is **readable by any process running as that uid**
once unlocked. Against the threat here, a prompt-injected agent running *as*
`arbeitandy`, all of them are theatre. Reaching for `secret-tool` would feel like
progress and change nothing.

The one mechanism with a kernel-enforced boundary is **`systemd-creds` in
host-key mode**: secrets encrypted against `/var/lib/systemd/credential.secret`
(root-owned, `0600`), decrypted by PID 1, delivered to a unit on a `0400` tmpfs.
The probe result is what makes this interesting — a rootless container cannot read
root-owned files, so a bind mount of either the ciphertext or the key yields
nothing.

Its limits, stated plainly rather than discovered later:

- **No TPM on this box** (measured). The host key rests on file permissions
  alone, so a disk image or host-root compromise defeats it. Against an injected
  agent that is fine; against Linode control-plane compromise it is not — and
  `sandbox.md` already scopes that out.
- **`arbeitandy` has `NOPASSWD:ALL`** — but a sandboxed agent cannot use it.
  Measured this session: `sudo -n id` fails under `no_new_privs`, and again on
  `/etc/sudo.conf is owned by uid 65534` (bwrap maps outside-root to `nobody`).
  So root ownership **is** a genuine boundary against the agent's own execution
  and against its rootless containers. Codex's blanket "root ownership is not a
  boundary" overstates it. The caveat that survives is narrower and still
  decisive: root ownership does not defend against an agent that persists into
  *your* unsandboxed, sudo-capable login. Fix the write scope and this holds.
- **Claude Code reads `~/.claude/.credentials.json` directly.** There is no
  credential-helper hook for subscription OAuth (`apiKeyHelper` covers API keys, a
  different auth path). So `systemd-creds` cannot be dropped in; it needs a
  wrapper that materialises the file into a mount namespace private to the agent's
  process tree. That is real work for a partial win.

**Recommendation: do not start here.** Treat `systemd-creds` as deployment
hygiene — no plaintext in units, command lines or backups — rather than as a
boundary against this threat. Principal separation delivers more, because it makes
the credential unreachable from a *different* principal without moving it at all.

### The option that actually removes secrets

Raised by Codex and worth more than everything above for the **non-OAuth**
credentials, because it deletes the long-lived secret rather than hiding it:

- **GitHub** — a GitHub App whose private key lives on another host, minting
  repo- and permission-scoped installation tokens that expire in an hour. Better
  still, have the broker perform the operation and never return a token.
- **Linode** — keep the PAT on the broker; expose allowlisted operations. Failing
  that, hand back a 2-hour OAuth access token instead of a permanent PAT.
- **SSH signing** — a remote signer or non-exporting agent. The private key
  becomes unexfiltratable; the residual risk changes shape into a *signing oracle*
  that malicious code can invoke while authorised. Add policy or human approval if
  arbitrary signing is unacceptable. This is the honest trade, not a free win.

Two rules for any such broker: it must expose **narrow actions with quotas and an
audit log**, never an endpoint returning the underlying secret; and Tailscale
identity alone is not authentication, because it trusts every process on the box.

The subscription OAuth tokens are the irreducible residue. With no
credential-helper interface, only an auth-terminating proxy could remove them, and
that is unsupported and fragile unless the clients bless it. Say so plainly rather
than engineering around it.

## Suggested order

Cheapest and most certain first; nothing here depends on spending money.

0. ~~**Close the write scope.**~~ **DONE 2026-08-04.** The obvious fix —
   `allowWrite: ["~/src", "/tmp"]`, as `sandbox.md` claimed — was rejected on
   measurement: `~/.cache` holds 3.3 GB of Go build cache and `~/go` 1.7 GB of
   module cache, so it would break every Go build on the box. What landed instead
   is a bounded `denyWrite` denylist of surfaces that execute on login or shadow a
   command: shell profiles, `~/.config/systemd`, `~/.local/bin`, agent hook config
   (including the `settings.local.json` override that was writable while
   `settings.json` was denied), and git config with `core.hooksPath`.

   Verified in-session with a control: `touch ~/.bashrc` and `~/.profile` now
   return `EROFS`, while `~/.cache` still writes. `devbox-smoketest` asserts each
   path individually — a count would pass while the one entry that mattered was
   removed — and is now 45 checks, up from 38.

   Two honest residuals. A denylist cannot cover unknown-unknowns, unlike the
   allowlist that was rejected. And `~/.local/share/mise` stays writable although
   its shims are on `PATH`, because denying it breaks `mise install`.
1. **`ip_unprivileged_port_start = 0`** in `common_sysctl`. One line, unblocks the
   compose tier, no security cost worth the name on a box with no inbound.
2. **Bake the toolbox image.** Measured: zero images cached, so every run
   re-installs socat/kubectl/helm/git/jq/psql from `debian:13-slim`. This is the
   speed win, and it is unrelated to RAM. **Drop zram** — the swapfile is at 0 B.
3. **Principal separation.** Highest security value per unit of effort. Start with
   `runner` (mechanical, no credential migration), then split the agent uids.
4. **Podman socket proxy.** Pairs with 3; without it `--network=host` stays open.
5. **Broker the non-OAuth secrets.** GitHub App first — it has the clearest
   supported path and the largest blast-radius reduction.
6. **Egress proxy + nftables enforcement.** Most moving parts, most likely to
   generate confusing failures, so last.

Also correct `sandbox.md` as part of step 0. A document that overstates a control
is worse than one that omits it, because it stops anyone looking.

## Open probes — settle these before building

Written as commands, because this repo keeps relearning that a property described
in prose decays silently while the same claim written as a probe fails loudly.

```bash
# 1. ANSWERED 2026-08-04 — kept for regression. Inside a Claude session, expect
#    BOTH to fail. If sudo ever succeeds, the root-owned boundary is gone.
sudo -n id                                    # want: no_new_privs refusal
touch ~/.bashrc.probe                         # want: EROFS, after step 0 lands

# 2. Does kind's serving cert carry the container-name SAN? If yes, socat goes away.
openssl s_client -connect iden2-dev-control-plane:6443 </dev/null 2>/dev/null \
  | openssl x509 -noout -text | grep -A1 'Subject Alternative Name'

# 3. Does --network=host sidestep an nftables uid/cgroup rule? Test before relying on it.
podman run --rm --network=host alpine:3.20 wget -qO- https://example.com

# 4. Can a second uid own a rootless podman socket the agent can reach?
#    Needs subuid/subgid ranges plus `loginctl enable-linger runner`.
grep runner /etc/subuid /etc/subgid
```

Every one of these has a cheap negative control. Use it — a blocked syscall and an
absent binary are indistinguishable from inside, and that false negative has cost
this project real time more than once.
