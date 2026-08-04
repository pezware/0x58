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

## ghcr mirrors — currently UNREACHABLE from this box, and not your fault

Every image we depend on is mirrored into **ghcr.io**, and that is where we would
rather pull from: no Docker Hub rate limits, and images we control.

**It does not work here, and no amount of retrying will fix it.** Measured
2026-08-04, same token, back to back:

| request | result |
|---|---|
| `GET /repos/iden2-com/go-monorepo/contents/README.md` | 200 |
| `GET /orgs/iden2-com/packages?package_type=container` | **403** |
| ghcr manifest read for `mirror/vault:1.20.4` | **403** |

The cause is a GitHub platform gap, not a misconfiguration: **fine-grained PATs
have no packages permission at all** — the permission simply does not exist in
the token UI — and ghcr accepts only *classic* PATs. Package visibility set to
"inherit from repo access" governs which **users** may pull; a token is a separate
principal and can never carry a scope GitHub never implemented for it.

So `gh auth token | podman login ghcr.io` **succeeds at login and still 403s on
the manifest**. That split is the confusing part: do not read a successful login
as proof of access.

**What to do meanwhile:** fall back to the upstream image, and say so in your
report. Many Dockerfiles here already document the fallback — e.g. the did-sync
init container takes `BASE_IMAGE=hashicorp/vault:1.20.4`. Prefer a documented
fallback over inventing one.

Do **not** propose minting a classic PAT to work around this. It is a long-lived
credential on disk, the exact thing this box's design avoids, and the intended
fix is making the `iden2-com/mirror/*` packages public — they mirror public
upstream images, so there is nothing to protect.

Re-test before assuming it is still broken; this is expected to change:

```bash
cd ~/src/iden2/<repo> && TOK=$(~/.local/bin/gh auth token)
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOK" \
  "https://api.github.com/orgs/iden2-com/packages?package_type=container"   # 200 = fixed
```

## kind

kind needs the podman provider explicitly, on top of the shim above:

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
```

Rootless podman cannot bind privileged host ports, so a cluster config mapping
80/443 needs unprivileged ports instead. Copy the config out and edit the copy
rather than mutating the repo's.

## Reaching the cluster: loopback TCP is still blocked

`allowAllUnixSockets` opened AF_UNIX. **It did not open loopback TCP**, and those
are separate restrictions — the sandbox has its own network namespace with only
`lo`, so host-published ports do not exist inside it. kind publishes its API
server on `127.0.0.1:<port>`, which is therefore unreachable however correct your
kubeconfig is. Do not debug the kubeconfig; it is not the problem.

The way through is a **toolbox container joined to the `kind` network**, driving
the cluster from inside podman's namespace:

```bash
docker run -d --name iden2-ctl --network kind \
  -v /run/user/1000/podman/podman.sock:/run/podman.sock \
  -v "$HOME/src:$HOME/src" \
  -v "$HOME/.local/share/mise/installs:$HOME/.local/share/mise/installs:ro" \
  -w <repo> <toolbox-image> sleep infinity
```

If the repo's own kubeconfig must work unmodified (it points at `127.0.0.1`), add
a `socat TCP-LISTEN:<port>,fork TCP:iden2-dev-control-plane:6443` inside that
container. Prefer pointing the kubeconfig `server` straight at
`iden2-dev-control-plane:6443` when you can — one less moving part, provided
kind's serving cert carries that SAN. **Verify the SAN before assuming**; falling
back to socat is fine and is what worked on 2026-08-04.

**Build the toolbox from an image that already has the tools.** `socat`,
`kubectl`, `helm`, `git`, `jq` and `psql` are all present on the *host* — none of
them are in a bare `debian:13-slim`, and `apt-get install`-ing them on every run
burned a large share of a 37-minute session. Host packages do not help a
container. If you find yourself apt-installing the same list twice, stop and bake
an image instead.

## Tear down when the work is done — this is your job, not the human's

**Order matters: tests green → PR/issue updated → then tear down.** Not before.
Review feedback routinely needs one more run against the same cluster, and
rebuilding it costs far more than keeping it for another ten minutes. Once the
report is posted, destroy it without being asked.

A cluster left running is not free on this box. Measured on 2026-08-04, teardown
returned **1.6 GB of RAM and 8 GB of disk** — on a 4 GB machine with **no swap**,
that is the difference between the next session working and being OOM-killed for
reasons that will look unrelated.

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
kind delete cluster --name iden2-dev
podman rm -f iden2-ctl kind-cache kind-cache-quay 2>/dev/null
podman image prune -f && podman volume prune -f
free -m | head -2; df -h / | tail -1        # report what actually came back
```

Be surgical, not scorched-earth. **Keep** the artifacts the next run reuses —
`dev/kind/.kubeconfig`, `dev/caddy/certs/`, `dev/keycloak/.env`, the mkcert CA in
`~/.local/share/mkcert/`. They are gitignored, cheap, and regenerating them is
slow. **Remove** only what this run created, and name anything you deliberately
left behind so the next session is not guessing.

Report the reclaimed numbers. "Tore down the cluster" is unfalsifiable; "memory
2482 → 897 MB, disk 24 → 16 GB, podman reports 0 images" is checkable, and it is
how you would notice a delete that silently half-failed.

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
