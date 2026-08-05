# Agent sandboxing on the devbox

Applied by `restore.sh` on Linux only:
[`claude-settings.json`](claude-settings.json) and
[`codex-devbox.config.toml`](codex-devbox.config.toml).

## What the devbox is for

State the goal first, because every trade-off below is only legible against it.

The devbox is an isolated environment where Claude — and Codex, when Claude calls
it — work the whole of `iden2` and `pezware` **comfortably**: build and test,
`git` and `gh`, kind and podman when a change needs them, and the ordinary Linux
tooling to debug the stack. They search documentation and references without
asking. **Neither lacking access nor excessive access is acceptable**, and of the
two, lacking access is the failure this box has actually suffered: twice a
control has stranded work it was never meant to stop.

The Mac is headquarters, not a second workplace. It manages the devbox lifecycle
and is where deeper debugging, auditing and review happen when they are needed.
Most work happens on the devbox. A mobile device connects occasionally, and that
path is proven.

The network rule is narrow, and worth stating exactly:

> Egress that Claude or Codex initiate — for search, for packages, for debugging —
> **is the point of the box.** Beyond that, nothing in and nothing out.

## The threat this addresses

Note what the goal does *not* say. Agents are relatively trusted here, and the
question is not whether Claude or Codex might misbehave. The answer to that is
bounded by two things that already hold: work of consequence lands in source
control and on GitHub, where it is reviewable and revertible, and the devbox
rebuild has been exercised rather than assumed. A bad session costs a rebuild.

So the exposure that matters is not the agent doing its job. It is everything
that is *not* that: an unattended listener, a background process dialing out, a
credential reachable by something with no business asking.

The devbox holds two subscription refresh tokens in plaintext on disk, which mint
new access tokens indefinitely until revoked. Linux has no Keychain equivalent,
so this is an accepted exception rather than a solved problem:

| file | what it buys | agent access |
|---|---|---|
| `~/.claude/.credentials.json` | the Claude account | **denied** |
| `~/.codex/auth.json` | a review subscription | **readable, deliberately** |

They are not worth the same, and that asymmetry is why they are not treated
alike — see the Codex trade-off below.

Tailscale and the Linode Cloud Firewall handle *inbound* well: the box has no
public listener and OpenSSH is disabled. Outbound they do not handle at all
(`outbound_policy` is `ACCEPT`). A domain allowlist inside the sandbox is the
wrong instrument for that gap, because it cannot tell agent-initiated traffic
from anything else — and the traffic it would block most reliably is the
reference search the box exists to do. What *can* tell them apart is the
sandbox's network shape: the session netns has loopback only, so every packet an
agent sends traverses the proxy. **That boundary, not the list of domains, is the
control.**

## What is configured

**Fail closed.** `failIfUnavailable: true` and `allowUnsandboxedCommands: false`.
By default Claude Code *warns and continues unsandboxed* when bubblewrap is
missing; that default converts a broken sandbox into no sandbox. This is also why
`bubblewrap` and `socat` are in [`packages.txt`](packages.txt) as required rather
than optional — without them Claude Code refuses to start, which is the intent.

**Credentials hidden.** `sandbox.credentials` (Claude Code 2.1.187+) denies reads
of `~/.claude/.credentials.json`, `~/.npmrc`, `~/.config/gh/hosts.yml` and
`~/.git-credentials`, and unsets `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
`GH_TOKEN`, `GITHUB_TOKEN`, `LINODE_TOKEN`, `NPM_TOKEN` and
`TF_VAR_tailscale_auth_key` for sandboxed commands. `~/.codex/auth.json` is
**not** in that list, deliberately.

**Filesystem.** Reads denied for `~/.gnupg`, `~/.config/gcloud`, `~/.kube`,
`~/.aws`, the Tailscale state directories and `/etc/0x58-node.env`. Note that
`~/.ssh` is **not** among them — it was removed deliberately on 2026-08-03 so
agents could sign and push; see the trade-offs below.

**Writes are a denylist over `~`, not an allowlist of `~/src`.** The allowlist
would be stronger, and it was rejected on measurement rather than principle:
`~/.cache` holds 3.3 GB of Go build cache and `~/go` 1.7 GB of module cache, so
confining writes to `~/src` breaks every Go build on the box. What landed instead
is a bounded denylist of the surfaces that **execute on login or shadow a
command** — shell profiles, `~/.config/systemd`, `~/.local/bin`, agent hook
config, and git config including `core.hooksPath`.

This matters more than it sounds. `arbeitandy` has `NOPASSWD:ALL`, so an injected
agent never needs to escalate itself: it writes a shell profile and waits for the
human's next unsandboxed login. `~/.claude/settings.local.json` is denied
alongside `settings.json` for the same reason — planting agent hooks in the
`.local` override is exactly how the 2026-08-04 npm worm persisted.

Be honest about what that leaves: a denylist cannot cover unknown-unknowns, and
`~/.local/share/mise` is knowingly still writable because its shims are on `PATH`
but denying it would break `mise install`. `devbox-smoketest` probes the
denylist one path at a time, so a regression fails loudly instead of silently.

**Egress is proxied and unrestricted. There is no domain allowlist.**
`allowedDomains` was removed on 2026-08-05. It had been documented as advisory
on the strength of one measurement showing it unenforced — and that measurement
was taken in a bridge session. In a *direct* session it enforces, which a real
session proved by failing: `binaries.prisma.sh` and `registry-1.docker.io`
returned nothing while `ghcr.io` (listed) answered, stranding a Prisma TLS
investigation on a box whose stated purpose is to let agents fetch what they
need.

A list that enforces in one session type and not another is worse than either
outcome on its own: it cannot be relied on as a control, and it cannot be relied
on to stay out of the way. Since the goal says agent-initiated egress *is* the
point, the list is gone rather than half-trusted.

What is load-bearing is the shape underneath, and it is unchanged: loopback-only
netns, and the `socat` listeners on `:3128`/`:1080` as the sole route out. The
boundary is the route, not a list of names.

## Four deliberate trade-offs

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
authorised the commit — it proves this box produced it. `user.signingkey` is an
on-disk *path* (`~/.ssh/devbox_agent`) and `IdentityFile` pins the same key for
github.com, so the devbox signs and pushes unattended with no agent and no Touch
ID tap. That is the documented success of the loop, not a regression — but prompt
injection here can push signed code to any repository the key reaches, which
rotating a token does not undo. Verify rather than trust it:

```bash
git config --get user.signingkey          # a path ⇒ signs with no agent, no tap
grep -A1 'Host github.com' ~/.ssh/config  # IdentityFile ⇒ pushes with no tap
```

**In-session Codex is worth a readable OpenAI token.** `~/.codex/auth.json` is
readable by sandboxed commands so `codex exec` works in-session, which is what
makes independent review part of the loop rather than something the human relays
by hand.

The two options were mutually exclusive by construction: a readable `auth.json`
buys in-session review at the cost of a readable OpenAI refresh token; a denied
one forces Codex through the broker or `codex-task`. The devbox is the workplace
and Codex is one of the two agents meant to work there, so it is readable. What
makes that cheap to hold is where the trust actually sits — that token buys a
review subscription, not the account, and a bad session costs a rebuild.

`~/.claude/.credentials.json` is a different proposition and stays denied. Keep
the pair asymmetric on purpose; the day both are readable, the rebuild stops
being a sufficient answer.

**AF_UNIX is open, and the Mac's key is safe for a different reason than it
looks.** `allowAllUnixSockets` is on for container tests, and a
bind/listen/connect round-trip was measured succeeding in-session on 2026-08-04.
Any claim that the sandbox blocks AF_UNIX is stale.

The forwarded Secure Enclave agent is unreachable because `94f29f4` set
`ForwardAgent no` for both `devbox` and `k8s` — having found ~620 stale
`/tmp/auth-agent*/` sockets on the box with live ones still answering. **The
socket is not blocked; it is not forwarded.** Prefer the weaker-sounding sentence:
it is the true one, and it names the thing that can be undone by habit rather
than by a config change. `sign-push` still asks for `ssh -A` by design; for the
length of that session the keys are reachable to anything on the box, so do not
run agent sessions and `sign-push` in the same window without meaning to.

Worth being precise, because it constrains every later decision: on Linux
`allowUnixSockets` is not merely impractical, it is **inert**. Its own schema
reads *"macOS only: Unix socket paths to allow. Ignored on Linux (seccomp cannot
filter by path)."* Blocking is a seccomp filter on `socket()`, and seccomp sees
register values, not the path behind the `connect()` pointer — dereferencing that
in-kernel would be a TOCTOU hazard. macOS Seatbelt resolves paths, so it can
allow one socket; Linux gets exactly one switch, `allowAllUnixSockets`, and it is
all-or-nothing. Any future "just allow this one socket" here is not a config
change, it is a decision to allow every socket including the SSH agent.

A caution for anyone probing this: `test -r` on a denied file returns *success*.
`access(2)` is not intercepted — only the actual read is.

**Container tests run inside agents, and the runtime sits outside the sandbox.**
Rootless podman's Docker-compatible socket answers from a sandboxed Bash call, so
agents run the `integration` and `e2e` tiers themselves. What that costs is
larger than the switch suggests:

> **The container runtime executes outside the sandbox, so anything delegated to
> it leaves the sandbox's view entirely.**

Measured, not inferred:

| delegated through podman | what it escapes |
|---|---|
| `docker pull docker.io/library/alpine:3.20` succeeded in-session | the proxy path — the pull originates outside the session netns |
| `-v $HOME:/m` reads paths a direct `cat` cannot | `filesystem.denyRead` — a real bypass of a control that still counts |

The bind-mount row is the one that bites. The credential deny-list blocks a
*direct* read — `~/.claude/.credentials.json` returns `Permission denied` — but a
bind mount reaches what `cat` cannot, and that is a genuine hole in the only
control the goal actually leans on.

So the honest statement of the posture is: the sandbox constrains the agent's own
syscalls, and stops being a containment boundary the moment work is handed to the
runtime. Hostile code belongs on the disposable k8s node, as it always did.

The trade is cheap, which is why it is easy to hold: **28 of 746** test files in
the go monorepo need containers, and they already sit behind `//go:build e2e` or
`integration` tags that a plain `go test ./...` skips. Agents run the other ~96%
sandboxed.

## How this file reaches the box — and why it drifts

[`claude-settings.json`](claude-settings.json) here is the source of truth. It
reaches the devbox through `git` and `restore.sh`, never by copying a file onto
the box. That is not fastidiousness; it is the specific failure this repo keeps
hitting. On 2026-08-04 the devbox was found running a skill file **144 lines
shorter** than the committed one, having simply never been re-restored — and the
stale copy told agents that container tests were impossible, which by then was
false. Nothing drifted maliciously. It drifted because a copy existed that no
commit governed.

There is a deliberate wrinkle worth knowing before it surprises you.
`restore.sh` will **not** overwrite an existing `~/.claude/settings.json`; it
lands the file beside it as `settings.0x58-sandbox.json` and tells you to merge.
That guard exists so a restore cannot silently drop hooks or permissions — but it
also means **settings changes never auto-apply**, and that is exactly the gap
through which the live file and this repo diverge.

So the honest workflow is: edit here, commit, pull on the box, restore, then
merge the sandbox block by hand and diff to confirm.

```bash
# on the devbox, after the change is merged to main
git -C ~/src/public/0x58 pull
python3 - <<'PY'   # compare the part that matters, ignoring key order and UI prefs
import json, os
a = json.load(open(os.path.expanduser('~/src/public/0x58/linux/claude-settings.json')))
b = json.load(open(os.path.expanduser('~/.claude/settings.json')))
print('sandbox block in sync:', a['sandbox'] == b['sandbox'])
PY
```

Compare **semantically, not byte-for-byte**. Claude Code rewrites the file with
its own key order and adds runtime UI preferences of its own
(`inputNeededNotifEnabled`, `agentPushNotifEnabled`); a `diff` reports those as
drift when nothing meaningful has changed, which trains you to ignore a signal
worth reading.

## Verify it is actually on

Configuration that silently does nothing is worse than none, because it creates
false confidence. Check rather than assume:

```bash
command -v bwrap socat                     # both must exist
claude --version                           # needs >= 2.1.187 for sandbox.credentials
python3 -m json.tool ~/.claude/settings.json >/dev/null && echo "settings parse OK"
ls ~/.codex/devbox.config.toml
```

Then, inside a Claude session on the devbox, confirm the deep lock holds *and*
that the deliberate exception is genuinely excepted. These two must disagree — if
both fail, Codex review is stranded; if both succeed, the lock is gone:

```
cat ~/.claude/.credentials.json     # must FAIL: Permission denied
codex login status                  # must SUCCEED: auth.json is readable on purpose
```

And confirm egress works and is *routed*. Both of these must succeed, because
reaching documentation is a capability the box owes an agent, not a leak:

```
curl -sS -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org
curl -sS -o /dev/null -w '%{http_code}\n' https://example.com
```

The control that replaced the allowlist is the route, so probe that instead —
there must be no way out that skips the proxy, and no interface but loopback:

```bash
curl --noproxy '*' -sS https://example.com   # must FAIL: could not resolve host
ip -o addr show                              # must show loopback only
```

A success on the first line is the real finding: it means a path exists that the
sandbox never sees.

And confirm the container socket is reachable. Run it in both places: a blocked
socket and an absent one look identical from inside, so the control run is what
makes the result mean anything.

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
- Kernel or bubblewrap escape.
- Anything handed to the container runtime, per the trade-off above.
- Reading source. Every repo on the box is readable by design — the sandbox
  protects credentials and shapes the network path, it does not make the source
  secret.
- **Where an agent chooses to send traffic.** This is not a gap, it is the goal:
  agent-initiated egress is unrestricted on purpose. What the posture asserts is
  that nothing *else* is talking.

For genuinely hostile code, use the disposable k8s node or a throwaway VM. Do not
run it on the box holding all source and the Claude credential.

And keep the recovery path exercised. It is doing more load-bearing work in this
posture than any single control listed above: the reason a trusted-agent model is
affordable here is that a bad session costs a rebuild, and that only stays true
while the rebuild is something recently done rather than recently described.

## Open items

Short-lived by intent. A sentence cannot fail, so everything here should either
become an assertion in [`devbox-smoketest`](../dev/nodes/devbox-smoketest) or
stop being true. Measured 2026-08-04 and re-checked 2026-08-05.

**Egress filtering was session-type dependent, and that is why the list is
gone.** Two measurements, both real, that took a day to reconcile:

| session | result |
|---|---|
| bridge (`CLAUDE_CODE_CHILD_SESSION=1`) | `example.com`, `pastebin.com`, `1.1.1.1` all answered; a `POST` to `httpbin.org` echoed back with the Linode's public IP as origin — **nothing filtered** |
| direct | `ghcr.io` (listed) → 401, `binaries.prisma.sh` and `registry-1.docker.io` (unlisted) → no connection — **filtered exactly per the list** |

The first was recorded as "the proxy is not filtering" and the allowlist demoted
to advisory. That conclusion was drawn from one session type and was wrong as a
general statement. The lesson is narrower than "verify twice": **a probe records
the behaviour of the session that ran it**, and on this box session type is a
variable, not a detail.

Nothing is open here any more — the list is removed, so neither behaviour can
strand work. What remains worth asserting is the boundary: that the netns is
loopback-only and nothing routes around the proxy.

**Those boundary checks cannot live in `devbox-smoketest` as it stands.**
`remote()` is `ssh … bash -lc`, an unsandboxed login shell, so `ip -o addr show`
there reports the host's real interfaces and `curl --noproxy '*'` succeeds. Both
would report FAIL on a healthy box — the same cry-wolf failure `4113fd9` had to
fix twice. Only "no listener answers off-tailnet" is honestly testable from the
Mac; the netns and route checks need either a live session or a sandboxed variant
of `remote()`.

**`/tmp` litter.** The ~620 stale `/tmp/auth-agent*/` sockets are gone — zero
agent sockets under any name, despite no reboot since 2026-08-03, so something
other than a rebuild cleared them. What is there instead is **2,093 empty
`claude-empty-*` directories**, roughly 830/day: bubblewrap's masking mounts, one
per denied path per session, never cleaned up. Harmless — `/tmp` is a 2 GB tmpfs
at 1% with a million free inodes, and a reboot clears it — but it is what will
mislead the next person who probes `/tmp` for stale sockets, because the
directory link count reads 2,106 and looks alarming until you list it.

**The Codex broker is built and has never run.** The unit exists at
`~/.config/systemd/user/codex-broker@.service`, `Linger=yes` is set, and
`/tmp/codex-broker/` exists but is empty with no instance loaded. With
`auth.json` readable the broker is no longer needed for in-session review, so
this is cleanup rather than a gap — but the headers of [`codex-task`](codex-task)
and [`codex-broker`](codex-broker) still claim the sandbox refuses AF_UNIX, which
is false, and they should be corrected or the scripts retired.
