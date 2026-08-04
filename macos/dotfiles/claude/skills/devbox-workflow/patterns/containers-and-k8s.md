# Container tests and the on-demand cluster

## What you can run

Since **2026-08-04**, container-backed tests run *inside* an agent session.
`allowAllUnixSockets` is enabled, so the podman socket answers from a sandboxed
Bash call. Anything you read claiming this is "structurally blocked" predates that
change — verify with the probe below rather than believing either version.

```bash
go test ./...                       # always worked
go test -tags=integration ./...     # works now
go test -tags=e2e ./...             # works now
```

## Getting a Docker-compatible endpoint

Two things are missing in-session, and both look like the runtime is broken:

- `XDG_RUNTIME_DIR` is unset, so podman derives the wrong socket path.
- There is no `docker` binary, which testcontainers and kind both look for.

A shim on `PATH` fixes both. Point it at the socket explicitly rather than
relying on `DOCKER_HOST`:

```bash
SHIM="$TMPDIR/bin"; mkdir -p "$SHIM"
for n in podman docker; do
  cat > "$SHIM/$n" <<'EOF'
#!/bin/bash
export XDG_RUNTIME_DIR="${PODMAN_SHIM_XDG:-/tmp/claude/xdgrt}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
exec /usr/bin/podman --remote --url unix:///run/user/1000/podman/podman.sock "$@"
EOF
  chmod +x "$SHIM/$n"
done
export PATH="$SHIM:$PATH"
docker version --format '{{.Server.Version}}'   # expect a podman version, e.g. 5.4.2
```

Verify with a control, because a blocked socket and an absent one are
indistinguishable from inside:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  --unix-socket /run/user/1000/podman/podman.sock http://d/_ping   # expect 200
```

## Pull from the ghcr mirror, and log in first

Every image we depend on is mirrored into **ghcr.io**. Prefer it over docker.io
and other upstream registries — it avoids Docker Hub rate limits and keeps you on
images we control.

ghcr needs authentication even for our mirrors. Run this **from inside the repo**,
so the `gh` wrapper selects the token matching the origin owner:

```bash
~/.local/bin/gh auth token | podman login ghcr.io -u arbeitandy --password-stdin
```

Do this **before** `kind create cluster` or any `task` target that pulls — a
mid-pull auth failure surfaces as an opaque image-pull error much later, usually
blamed on the cluster rather than the registry.

If login fails on permissions, the PAT likely lacks `read:packages`. Report that
rather than quietly falling back to upstream: the token scope is the fix, and a
silent fallback hides it.

## kind

kind needs the podman provider explicitly, on top of the shim above:

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
```

Rootless podman cannot bind privileged host ports, so a cluster config mapping
80/443 needs unprivileged ports instead. Copy the config out and edit the copy
rather than mutating the repo's.

## What the open socket costs — read before running anything untrusted

The container runtime runs **outside** the sandbox, so work handed to it is not
covered by the sandbox's limits. Two measured consequences:

- **Egress allowlisting is bypassed.** `docker.io/library/alpine:3.20` pulled
  successfully in-session even though `docker.io` is not in `allowedDomains`. The
  allowlist filters the sandboxed process's own sockets, not what a daemon does
  on its behalf.
- **File denials are bypassable the same way.** A bind mount is performed by the
  service, so `-v $HOME:/m` reaches paths the sandbox denies you directly.

The credential deny-list still stops a *direct* read, and both subscription token
files remain denied. But the sandbox is no longer a containment boundary for
anything that reaches the runtime. Treat "the sandbox will catch it" as false
here.

For genuinely hostile code use the disposable k8s node or a throwaway VM — not
the box holding all source and both subscription credentials.

## The k8s node

A separate, disposable Linode node for cluster work. Still useful when you want a
real Docker rather than rootless podman, or a cluster that can bind 80/443.
**It bills hourly and is not always on.**

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
