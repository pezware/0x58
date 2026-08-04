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

`sandbox.md` names this as the control that matters:

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

Severity is bounded by what still holds: `~/.claude/.credentials.json` and
`~/.codex/auth.json` both return `Permission denied`, so there is no token to
exfiltrate through the open path *by a direct read*. The deepest lock held; the
compensating one did not. Note the two combine badly with the already-documented
podman escape — that one bypasses the allowlist via the container runtime, but as
of this finding no escape is needed.

**Proposed fix:** add the negative case to `devbox-smoketest`. The current
verification in `sandbox.md` asks a human to eyeball two `curl` outputs, which is
exactly how this survived. Assert that a non-allowlisted host **fails**:

```bash
curl -sS -o /dev/null --max-time 10 https://example.com \
  && { echo "FAIL: egress allowlist not enforced"; exit 1; }
```

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
| `070e22b` | 2026-08-03 | *"let agents run container tests"* — **re-added** `"path": "~/.codex/auth.json"` in the same hunk that added `"allowAllUnixSockets": true`. Codex broke. |

So a feature was silently reverted one commit after it landed, by a commit about
something else. `sandbox.md` records the re-add as deliberate:

> `~/.codex/auth.json` was added to `sandbox.credentials.files` on 2026-08-04
> after it turned out to be listed only under `denyWrite` while this document
> claimed it was denied outright.

That reasoning is sound in isolation — the file *was* less protected than the doc
claimed. What went unnoticed is that closing the gap undid `c99f538`'s entire
purpose. Both commits are defensible; the pair is incoherent, and nothing failed
loudly to say so.

**Decide which you want** — these are mutually exclusive by construction:

- **Independent in-session review** — auth.json readable. Costs: an injected
  agent can read an OpenAI refresh token. Given finding #1, it could also send
  it somewhere.
- **Token stays denied** — Codex reaches the box through the broker (below) or
  through `codex-task`, and never through the sandbox's own credential reads.

The broker is the design that gives both, and per finding #3 it is now viable.

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
is gone. `sandbox.md` still claims the Mac's key is unreachable because "seccomp
blocks the syscall, not the path" — **that sentence is now false** and should be
treated as a live question, not a correction to make in passing: if the Secure
Enclave socket is forwarded to this box, a sandboxed agent can now reach it.
Verify before assuming either way.

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

**Fix pending an end-to-end pong.** Do not rewrite the three headers on the
strength of the probe above: `bind()`/`connect()` succeeding is necessary but not
sufficient for the broker's JSON-RPC handoff, and this repo's discipline is not
to write a claim down until something has actually exercised it. Confirm
`sessionRuntime.mode` flips from `direct` to a broker endpoint first.

---

## Re-running these

```bash
# 1. egress — the first must succeed, the second must FAIL
curl -sS -o /dev/null -w '%{http_code}\n' https://registry.npmjs.org
curl -sS -o /dev/null -w '%{http_code}\n' https://example.com

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

Finding #1 is a control documented as load-bearing that was never asserted.
Finding #2 is a feature reverted by an unrelated commit with no test to notice.
Finding #3 is a constraint that stopped applying, where the *good* news went
unrecorded for two days and left two scripts built around a limit that was gone.

The pattern is not that the prose was careless — this repo's prose is unusually
careful, and it corrected itself twice before this. The pattern is that a
sentence cannot fail. Prefer asserting in `devbox-smoketest` over describing
here; entries in this file should be short-lived.
