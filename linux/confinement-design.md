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

The last three are the foundation of everything below. Without the negative
control the first of them would have been unfalsifiable: a blocked read and a
broken mount look identical from inside.

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

## The control that does the most work: a runner uid

The measured facts point at an option that is cheaper than SELinux and stronger
than either proxy, and it follows from one line of reasoning:

- The agent **must** be able to read its own token, or it cannot authenticate.
- Therefore any process running as the agent's uid can read it.
- A container the agent starts runs as the agent's uid.
- ⇒ File permissions alone **cannot** both authenticate the agent and deny its
  containers the token. That is not a configuration gap; it is arithmetic.

There are only two ways out, and they compose well:

**1. Stop the containers from running as the agent's uid.** Give podman its own
unprivileged account — call it `runner` — with its own subuid range and a
lingering user socket. The agent talks to `runner`'s socket instead of its own.
Containers then execute as a uid that cannot read `arbeitandy`'s `0600` files at
all, which the probe above shows is a genuine kernel-enforced boundary rather than
a policy hope. `~/src` stays reachable by granting `runner` group access to it
specifically, which is exactly the scope that ought to be shareable.

**2. Filter what the API will accept.** A socket proxy in front of the podman
API that rejects `HostConfig.Binds` outside an allowlist and refuses
`Privileged: true`, `--network=host`, and `--pid=host`. This is the layer where
"which mount is legitimate" is actually decidable, which is precisely what MAC
could not do.

Together these close both measured bypasses. Neither requires relocating a single
credential.

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
- **`arbeitandy` has `NOPASSWD:ALL`.** Root-only protection means nothing to
  anyone who can `sudo cat`. Whether a *sandboxed* agent can invoke sudo — bwrap
  sets `PR_SET_NO_NEW_PRIVS`, which should defeat setuid — is **unverified and
  load-bearing**. See the open probes.
- **Claude Code reads `~/.claude/.credentials.json` directly.** There is no
  credential-helper hook for subscription OAuth (`apiKeyHelper` covers API keys, a
  different auth path). So `systemd-creds` cannot be dropped in; it needs a
  wrapper that materialises the file into a mount namespace private to the agent's
  process tree. That is real work for a partial win.

**Recommendation: do not start here.** The runner uid delivers most of the same
protection, because it makes the credential unreachable from the container
without moving it. Revisit `systemd-creds` only if the threat model widens to
include a compromised agent binary rather than an injected prompt.

## Suggested order

Cheapest and most certain first; nothing here depends on spending money.

1. **`ip_unprivileged_port_start = 0`** in `common_sysctl`. One line, unblocks the
   compose tier, no security cost worth the name on a box with no inbound.
2. **Bake the toolbox image.** Measured: zero images cached, so every run
   re-installs socat/kubectl/helm/git/jq/psql from `debian:13-slim`. This is the
   speed win, and it is unrelated to RAM. **Drop zram** — the swapfile is at 0 B.
3. **Runner uid.** Highest security value per unit of effort.
4. **Podman socket proxy.** Pairs with 3; without it `--network=host` stays open.
5. **Egress proxy + nftables enforcement.** Most moving parts, most likely to
   generate confusing failures, so last.

## Open probes — settle these before building

Written as commands, because this repo keeps relearning that a property described
in prose decays silently while the same claim written as a probe fails loudly.

```bash
# 1. LOAD-BEARING. Can a sandboxed agent escalate? Run INSIDE a Claude session.
#    If sudo succeeds, every root-owned protection above is decorative.
sudo -n id

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
