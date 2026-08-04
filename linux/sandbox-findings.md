# Sandbox findings — open items

Findings from probing the devbox sandbox from inside a Claude session on
2026-08-04. Each entry states the claim, the probe that tested it, and what the
probe returned. Nothing here is inferred from reading config alone — where a
cause is uncertain, it says so.

Companion to [`sandbox.md`](sandbox.md), which describes the intended posture.
This file tracks where the posture and the box disagree.

Status key: **OPEN** — confirmed, unfixed. **STALE-DOC** — the box is fine, the
prose is wrong. **FIXED** — with the commit that closed it.

---

## 1. The egress allowlist is not enforced — OPEN

`sandbox.md` named this as the control that matters — the claim this finding
retires:

> The egress allowlist is named above as the one thing that stops an injected
> agent exfiltrating a refresh token, since the Linode firewall's
> `outbound_policy` is `ACCEPT`.

It does not hold. Measured in-session:

```
example.com   → 200, genuine Cloudflare-served content (not a block page)
pastebin.com  → 200
1.1.1.1       → 301
POST https://httpbin.org/post -d 'canary=...'
  → remote echoed the payload back
  → origin logged by remote: 66.228.43.67   (the Linode's public IP)
```

None of those appear in `sandbox.network.allowedDomains`. A payload left the box
and the receiving host logged the real source address.

This is **not** configuration drift. The live `~/.claude/settings.json`
`allowedDomains` is byte-identical to [`claude-settings.json`](claude-settings.json)
in this repo. The config is right and is not being applied.

The proxy is the sole egress path, which makes the result unambiguous:

```bash
curl --noproxy '*' https://example.com     # curl: (6) Could not resolve host
```

The session netns has loopback only, so every packet must traverse the `socat`
listeners on `:3128`/`:1080` that bridge to a host-side unix socket. That path is
not filtering.

**Cause is not established.** This session carries `CLAUDE_CODE_CHILD_SESSION=1`
and a `CLAUDE_CODE_BRIDGE_SESSION_ID`, i.e. it runs through a remote/bridge
harness whose own proxy is the network path — plausibly the local `settings.json`
`network` block is simply not the enforcement layer in that mode. Worth noting
the harness's *own* allowlist (a near-identical list plus `pkg.go.dev`,
`docs.claude.com`) is not being applied either, which argues the failure is in
the proxy rather than in which list wins. Confirm before designing a fix.

What still holds is the control that the posture should have been leaning on all
along: `~/.claude/.credentials.json` and `~/.codex/auth.json` both return
`Permission denied`, so neither token leaves *by a direct read*. The deep lock
held. The one that did not was never the right instrument — see below.

The exposure worth tracking is therefore the podman bind-mount already documented
in `sandbox.md`, which reaches both files by a route the deny-list does not see.
That is a hole in a control the goal genuinely leans on, and it does not depend
on egress being filtered or unfiltered.

**The fix is not "turn it on."** Two things are wrong with the obvious
assertion, and only one of them is technical.

*Technical:* [`devbox-smoketest`](../dev/nodes/devbox-smoketest) reaches the box
through `remote()`, which is `ssh … bash -lc` — an **unsandboxed login shell**. A
`curl` run there is supposed to reach `example.com`, so asserting that it fails
would report FAIL on a healthy box while never touching the sandbox. The
smoketest already states this constraint beside its credential checks: the honest
in-session control needs a live Claude session, and "a smoke test must not depend
on a judgement call landing one way."

*Larger:* a domain allowlist is the wrong **shape** of control for what this box
is for. The devbox exists so Claude and Codex can work the whole of `iden2` and
`pezware` comfortably — build, test, `git`, `gh`, kind/podman, the Linux tooling
to debug the stack, and **search for documentation and references**. Egress the
agent initiates is the point, not the risk. The posture wants *nothing else in,
nothing else out*, and a list of package registries cannot express that: what
separates agent traffic from everything else is not the domain, it is the netns
and proxy boundary — which already exists and is measurable.

So `allowedDomains` is **advisory** as of 2026-08-04 — a record of what the box
routinely needs, not a containment boundary. Nothing rests on it, and
`sandbox.md` no longer claims otherwise.

What stays OPEN is therefore not "enforce the list" but "confirm the boundary
holds", asserted in `devbox-smoketest` through its `ok`/`no` helpers so a failure
counts and prints instead of aborting the run:

| assert | the claim it actually tests |
|---|---|
| no listener answers off-tailnet | no other ingress — the half the firewall does enforce |
| the session netns has loopback only | every agent packet must traverse the proxy |
| `curl --noproxy '*'` cannot resolve | there is no route around the proxy |
| an arbitrary docs host **succeeds** in-session | the capability the box exists to provide |

The last row is the inversion worth noticing: under this goal the failing test is
an agent that *cannot* reach a reference site, not one that can.

The measurement above still matters to that boundary, because the proxy not
filtering and the proxy not being in the path are the same observation until one
of them is ruled out. The `--noproxy` control argues it is in the path. Confirm
that before trusting the row above.

---

## 2. In-session Codex broke on 2026-08-03 — OPEN

Codex ran in-session before and does not now. `codex exec` dies with
`Permission denied (os error 13)`; `codex login status` fails identically. The
only unreadable path in `~/.codex/` is `auth.json` — `config.toml` reads fine and
the directory lists fine. The plugin's own check agrees:

```json
{ "ready": false,
  "codex": { "available": true, "detail": "codex-cli 0.144.1" },
  "auth":  { "available": true, "loggedIn": false, "requiresOpenaiAuth": true },
  "sessionRuntime": { "mode": "direct" } }
```

This is a **regression, not a wall**, and git dates it precisely:

| commit | date | effect |
|---|---|---|
| `c99f538` | 2026-08-03 | *"let the agent run Codex in-session for independent review"* — **removed** `~/.codex/auth.json` from the credentials deny list. Codex worked; the message records "Verified in-session afterwards: exit 0, model gpt-5.6-terra." |
| `070e22b` | 2026-08-03 | *"let agents run container tests"* — **re-added** `"path": "~/.codex/auth.json"` in the same commit that added `"allowAllUnixSockets": true`. Codex broke. |

Two hours and forty-seven minutes apart, same evening. So a feature was silently
reverted one commit after it landed, by a commit about something else.
`sandbox.md` records the re-add as deliberate:

> `~/.codex/auth.json` was added to `sandbox.credentials.files` on 2026-08-04
> after it turned out to be listed only under `denyWrite` while this document
> claimed it was denied outright.

(The one-day discrepancy is a timezone artifact, not a second change: `070e22b`
is 2026-08-03 23:47 CDT, which is 2026-08-04 04:47 UTC.)

That reasoning is sound in isolation — the file *was* less protected than the doc
claimed. What went unnoticed is that closing the gap undid `c99f538`'s entire
purpose. Both commits are defensible; the pair is incoherent, and nothing failed
loudly to say so.

**Decided 2026-08-04: in-session Codex.** The two options were mutually exclusive
by construction — a readable `auth.json` buys independent in-session review at the
cost of a readable OpenAI refresh token; a denied one forces Codex through the
broker or `codex-task`. The devbox is the workplace, and Codex is one of the two
agents meant to work there, so `~/.codex/auth.json` should be readable again and
`070e22b`'s re-add stands as an unintended revert of `c99f538` rather than a
posture change.

What makes that cheap to hold is where the trust actually sits: in source control
and in a devbox rebuild that has been exercised. The OpenAI token buys a review
subscription, not the account — `c99f538` drew that line already ("Codex's token
buys a review; the Claude refresh token buys the account"), and it still holds.

The broker is not the reason for this decision, and per finding #3 it remains
worth building — it is the route that would give independent review *without* a
readable token. This decision means Codex works today; it does not retire the
broker.

**The settings change belongs in its own commit**, not in this file. Until
`~/.codex/auth.json` is removed from `sandbox.credentials.files` in
[`claude-settings.json`](claude-settings.json) *and* restored onto the box, this
entry stays OPEN — the decision is recorded, not applied.

**Do not "fix" this by running `codex login`.** `loggedIn: false` is the
sandbox's view, not the box's — `auth.json` exists on the host, it is masked from
the session. Check with `codex login status` from an unsandboxed shell before
touching auth; re-authenticating would be treating a visibility problem as a
credential problem.

---

## 3. The AF_UNIX "dead end" is no longer true — STALE-DOC

[`codex-task`](codex-task) and [`codex-broker`](codex-broker) both rest on this,
verified 2026-08-02:

> the sandbox refuses AF_UNIX outright, not per-path. Claude cannot even
> `listen()` on a socket it creates itself under `/tmp` [...] Connect fails EPERM
> at `socket()` — before the path is ever considered

A third file carries the same claim, and it is the one that matters most.
[`sign-push`](sign-push) gives it as the *reason agent commits are unsigned*:

> Agents on this box commit UNSIGNED, deliberately: signing needs the forwarded
> SSH agent, whose socket is AF_UNIX, and Claude Code's sandbox refuses AF_UNIX
> at `socket()`.

Unlike the other two — design notes for a route nobody has walked — that sentence
justifies a live policy. With `sandbox.md` this is **four** stale claims, not
three.

Measured 2026-08-04 from inside a session:

```
socket()+bind()+listen() SUCCEEDED -> /tmp/claude-1000/afunix-probe.sock
connect() SUCCEEDED — AF_UNIX round-trip works
```

The podman socket answers too (`/_ping` → `200`). `allowAllUnixSockets: true`,
added in `070e22b` so container tests could run, un-blocked AF_UNIX as a side
effect — and `070e22b` is the same commit that broke Codex in finding #2. The
broker route became viable in the very commit that made it necessary again.
Nobody noticed, because the win arrived as a side effect of an unrelated change.

Note this also retires the *stated reason* AF_UNIX was kept blocked. `c99f538`
put it plainly: *"the broker route needs AF_UNIX which stays blocked because that
is what keeps the forwarded Secure Enclave agent unreachable."* That protection
is gone, and `sandbox.md` still claims the Mac's key is unreachable because
"seccomp blocks the syscall, not the path" — **that sentence is now false.**

**This was already caught and already fixed.** `94f29f4` set `ForwardAgent no` for
both `devbox` and `k8s` in
[`0x58-devbox`](../macos/dotfiles/ssh/config.d/0x58-devbox), reaching the same
conclusion from the other direction and measuring the exposure while it lasted:

> The risk was not theoretical once AF_UNIX opened up for container tests
> (linux/sandbox.md): a sandboxed agent can now reach any unix socket, and ~620
> stale `/tmp/auth-agent*/` sockets had accumulated on the box, live ones still
> answering with both Secure Enclave keys.

So the Mac's key is safe again — but not for the reason `sandbox.md` gives. The
socket is not blocked; it is **not forwarded**. That distinction is the whole
finding, because it moves the control from a kernel filter to an SSH client
option, and only one of those survives a habit.

Two residues, both narrower and both real:

- **`sign-push` still says `ssh -A`** (`ssh -A devbox`, and it is right to — the
  agent is the whole mechanism). For the length of that session the SE keys are
  forwarded onto a box where AF_UNIX is open. It is opt-in and human-initiated,
  which is the design, but it is no longer true that *nothing* can reach them.
  Do not run agent sessions and `sign-push` in the same window without meaning to.
- **The ~620 stale sockets.** `94f29f4` found live ones still answering. `/tmp`
  survives until reboot, so a rebuild clears them and an uptime does not. Worth a
  probe, and worth an assertion once probed.

Everything else the broker needs is already in place — unit at
`~/.config/systemd/user/codex-broker@.service`, `Linger=yes`,
`allowUnixSockets` pre-declaring the three paths. Only the broker is not running
(`/tmp/codex-broker/` is absent, and `/tmp` is shared with the host, so that is a
real absence and not a namespace artifact).

Start it from an unsandboxed shell — a session cannot, as `systemctl --user`
gives `Failed to connect to user scope bus` inside the PID namespace, which is
the boundary working as intended:

```bash
systemctl --user enable --now \
  codex-broker@$(systemd-escape /home/arbeitandy/src/public/0x58).service
```

**Fix pending an end-to-end pong.** Do not rewrite the four headers on the
strength of the probe above: `bind()`/`connect()` succeeding is necessary but not
sufficient for the broker's JSON-RPC handoff, and this repo's discipline is not
to write a claim down until something has actually exercised it. Confirm
`sessionRuntime.mode` flips from `direct` to a broker endpoint first.

`sandbox.md` is the exception, corrected in this change: that AF_UNIX is open is
measured, and the file asserted both "AF_UNIX stays blocked" and
"`allowAllUnixSockets` is on" seventy lines apart. A self-contradiction needs no
pong to resolve. The three *script* headers wait, because what they claim is that
the broker route is impossible — and only a working broker disproves that.

---

## Re-running these

```bash
# 1. egress — BOTH must succeed. A registry the box needs and a docs host an
#    agent might reach for are the same claim now: agent-initiated egress works.
curl -sS -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org
curl -sS -o /dev/null -w '%{http_code}\n' https://example.com
#    The boundary is the control, so probe that instead of the domain:
curl --noproxy '*' -sS https://example.com   # expect: could not resolve — no route around the proxy
ip -o addr show                              # expect: loopback only in the session netns

# 2. codex — auth.json must be the only unreadable path under ~/.codex
cat ~/.codex/auth.json                       # expect: Permission denied
node "$(find ~/.claude/plugins/cache -name codex-companion.mjs | sort -V | tail -1)" \
  setup --json                               # expect: sessionRuntime.mode

# 3. AF_UNIX — bind/listen/connect round-trip
python3 - <<'PY'
import socket, os
p = os.environ.get("TMPDIR", "/tmp") + "/afunix-probe.sock"
try: os.unlink(p)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(p); s.listen(1)
c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); c.connect(p)
print("AF_UNIX round-trip OK"); c.close(); s.close(); os.unlink(p)
PY
```

## A note on how these were found

All three are the same failure mode, and it is the one `sandbox.md` already names:

> a security property described in prose decays silently, while the same claim
> written as a probe fails loudly.

Finding #1 is a control documented as load-bearing that was never asserted —
and, it turned out, was not the control the box wanted anyway.
Finding #2 is a feature reverted by an unrelated commit with no test to notice.
Finding #3 is a constraint that stopped applying, where the *good* news went
unrecorded for two days and left three scripts built around a limit that was
gone.

The pattern is not that the prose was careless — this repo's prose is unusually
careful, and it corrected itself twice before this. The pattern is that a
sentence cannot fail. Prefer asserting in `devbox-smoketest` over describing
here; entries in this file should be short-lived.

One correction to that lesson, earned by finding #3: writing the probe is not
enough if nobody re-reads the answer. `94f29f4` had already measured the Secure
Enclave exposure and closed it two days before this file re-derived it as an open
question. The probe fired; the finding was recorded in an SSH config comment
where nobody looking at the sandbox posture would pass it. **Assertions belong in
`devbox-smoketest`, and conclusions belong here** — a fix landing somewhere
unrelated is how a repo re-discovers its own work.
