# Container tests and the on-demand cluster

## What you can and cannot run

```bash
go test ./...                       # works in-session — ~96% of the suite
go test -tags=integration ./...     # cannot work in-session
go test -tags=e2e ./...             # cannot work in-session
```

Container-backed tests are unreachable from inside an agent session. Not
misconfigured — **structurally unavailable**:

| probe | inside session | outside |
|---|---|---|
| podman unix socket | `exit 7` | `200` |
| loopback TCP | `exit 7` | `200` |

Loopback TCP is podman's usual fallback, and it is blocked too. No `DOCKER_HOST`
value changes this. If you find yourself setting `DOCKER_HOST`, stop.

**Why it is not fixed:** on Linux the only switch is `allowAllUnixSockets`, which
is all-or-nothing — seccomp cannot filter by path. Enabling it would also expose
the forwarded Secure Enclave agent. The cost of refusing was measured: **28 of 746**
test files in the go monorepo need containers, and they already sit behind
`//go:build e2e|integration` tags that a plain `go test ./...` skips.

So: run the tagged tiers **outside** a session, or let CI do it. Report honestly
that you skipped them rather than implying the suite passed.

```bash
# from a normal shell on the devbox, not from a session
go test -tags=integration ./path/...
```

Rootless podman is installed and works there. `DOCKER_HOST` is already set in
`bashrc` when the socket exists, with `TESTCONTAINERS_RYUK_DISABLED=true` (Ryuk
wants a privileged container rootless podman will not grant).

## The k8s node

A separate, disposable Linode node for cluster work — kind, kubectl, anything
genuinely hostile. **It bills hourly and is not always on.**

```bash
cd ~/src/public/0x58/dev/nodes
./ts-node k8s apply          # ~$0.072/hour from this moment
./ts-node k8s ssh
./ts-node k8s destroy        # DO NOT SKIP
```

Creating or destroying it is **outward-facing and costs money** — get explicit
go-ahead first, both times. Leaving one running overnight costs more than a month
of the devbox's own volume.

Notes:

- Swap is forced to **0** on this role, enforced by a `lifecycle.precondition`.
  kubelet refuses to start with swap enabled unless explicitly configured.
- After `destroy`, **delete the node from the Tailscale admin console**. A stale
  record holds the hostname, so the next `apply` joins as `pezware-k8s-1` and every
  script addressing it by name breaks against a healthy box.
- The devbox reaches the k8s node over the tailnet; the reverse is blocked by ACL.
  That direction is deliberate — the disposable box runs the untrusted work.

For genuinely hostile code, use this node or a throwaway VM. Do not run it on the
devbox, which holds all source and both subscription credentials.
