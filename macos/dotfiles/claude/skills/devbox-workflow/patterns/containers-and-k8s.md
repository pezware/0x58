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

These are the capability probe — what the sandbox permits — not the interface you
should reach for first. `task --list` is: a task carries the env contract these
bare commands drop. The exception, and why the raw form still appears throughout
this file, is that per-service tasks are `internal: true` and therefore
uninvokable; see step 6 of [SKILL.md](../SKILL.md).

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

**Do not skip the `XDG_RUNTIME_DIR` line in that shim.** Left unset — which is its
state in every agent session — podman derives `/run/user/$(id -u)`, which is not
writable in the sandbox, and fails with `chmod /run/user/1000/libpod: read-only
file system` or, once past that, `newuidmap: write to uid_map failed: Operation
not permitted`. Both read like a fundamental privilege wall and are not one; they
are simply the wrong runtime directory. Pointing it at `/tmp` fixes both, and
`--remote` alone does **not** — podman initialises local runtime state regardless
of where the API calls go. Verified 2026-08-04, after this exact detour cost a
session real time and produced a confidently wrong "the CLI cannot work
in-session" conclusion.

### `docker compose`

`podman compose` is only a wrapper around an external provider and fails with
`looking up compose provider failed` when none is installed. `docker-compose`
(the Go, Compose-spec implementation) is installed by `restore.sh` for exactly
this, so compose stacks run unmodified:

```bash
docker-compose up -d           # or, through the shim above: docker compose up -d
```

If it reports `looking up compose provider failed`, the provider is missing
rather than broken — re-run `restore.sh`, do not reach for `pip install
podman-compose`.

Verify with a control, because a blocked socket and an absent one are
indistinguishable from inside:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  --unix-socket /run/user/1000/podman/podman.sock http://d/_ping   # expect 200
```

## ghcr mirrors — working since 2026-08-04

Every image we depend on is mirrored into **ghcr.io**, and that is where to pull
from: no Docker Hub rate limits, and images we control.

This section read **UNREACHABLE** until 2026-08-04, and the old diagnosis was not
wrong — it is still true and still worth knowing. **Fine-grained PATs have no
packages permission at all**; the permission does not exist in the token UI, and
ghcr accepts only *classic* PATs. Package visibility set to "inherit from repo
access" governs which **users** may pull; a token is a separate principal and can
never carry a scope GitHub never implemented for it. No configuration fixes that.

What changed is that a classic PAT scoped to `read:packages` **and nothing else**
now exists on the box. Same calls that used to 403, measured 2026-08-04:

| request | before | now |
|---|---|---|
| `GET /orgs/iden2-com/packages?package_type=container` | 403 | **200** |
| `GET /orgs/pezware/packages?package_type=container` | 403 | **200** |
| ghcr tag list for `mirror/vault` | 403 | **200** — `1.18`, `1.20.4` |
| `docker pull ghcr.io/iden2-com/mirror/vault:1.20.4` through the shim | 403 | **pulled** |

Those 200s were measured by exporting `GHCR_TOKEN` **by hand**. The `gh` wrapper
selected only by owner until 2026-08-15, so a plain `gh api /orgs/.../packages`
kept getting a Contents:READ token and kept 403ing — with the token that fixes it
sitting unused in the same credentials file. A session on 2026-08-15 concluded
from that 403 that *the box* could not query GHCR and fell back to weaker
evidence, which is the honest reading of what it saw: from inside a wrapper that
picks your token silently, "the token I was handed lacks this" and "this box
cannot do this" are indistinguishable.

The wrapper now selects `GHCR_TOKEN` for `/orgs/*/packages`, `/users/*/packages`
and `/user/packages`, from any directory, so **just call it**:

```bash
gh api "/orgs/iden2-com/packages?package_type=container" --jq 'length'   # 30 (of 60)
```

**The shim is podman, so YOU authenticate.** `macos/restore.sh` installs it as
`ln -sf podman ~/.local/share/kind-shims/docker`, so `docker` and `podman` are one
binary. It reads credentials from files on your side of the sandbox. No service
authenticates for you.

An earlier version of this section said the opposite — that the podman **service**
holds the login, and that a `docker pull` through the shim carries no credentials.
That was wrong. On 2026-08-23 it cost a session: told not to log in, and given no
working alternative, it logged in with the first iden2 token it found.

**Which file podman reads, in order.** It stops at the first file holding an entry
for the registry:

1. `$REGISTRY_AUTH_FILE`, or `--authfile`
2. `$XDG_RUNTIME_DIR/containers/auth.json` — that is
   `~/.cache/podman-run/containers/auth.json` once `kind-shims/env.sh` is sourced,
   **not** `/run/user/1000/...`
3. `~/.config/containers/auth.json`
4. `~/.docker/config.json`

A wrong credential high in that list beats a correct one below it. That is how a
`podman login` makes a working box stop working.

**Use `GHCR_TOKEN`. Never `GH_TOKEN_IDEN2` or `GH_TOKEN_PEZWARE`.** Both of those
are fine-grained (`github_pat_`, 93 characters) and carry no packages permission,
for the reason given above. `GHCR_TOKEN` is classic (`ghp_`, 40 characters).
Measured against `mirror/waltid-issuer-api:0.20.0` on 2026-08-23:

| credential | ghcr manifest read |
|---|---|
| `GHCR_TOKEN` (classic, `read:packages`) | **200** |
| `GH_TOKEN_IDEN2` (fine-grained) | 403 `DENIED: requested access to the resource is denied` |
| no credential | 403 `DENIED: invalid token` |

**`Login Succeeded!` is not evidence.** The ghcr `/v2/` endpoint accepts any
credential, including one that it then refuses every pull with. Judge a login by a
pull, never by its own output.

**Name the token you hold, in one request.** The response headers separate the two
kinds:

```bash
curl -sI -H "Authorization: token $TOKEN" https://api.github.com/user \
  | grep -iE '^(x-oauth-scopes|x-accepted-github-permissions)'
```

| header you get back | token kind | ghcr pull |
|---|---|---|
| `x-oauth-scopes: read:packages` | classic | works |
| `x-accepted-github-permissions: allows_permissionless_access=true`, no `x-oauth-scopes` | fine-grained | `denied` |

**`--creds` settles it with no precedence ambiguity.** It bypasses every auth
file, so it separates "wrong token" from "podman read the wrong file":

```bash
set -a; . ~/.config/0x58/credentials.env; set +a
podman pull --creds "arbeitandy:$GHCR_TOKEN" ghcr.io/iden2-com/mirror/postgres:17.2
```

If `--creds` works and a bare `docker pull` does not, the credential is fine and
an auth file is the problem. Read them in the order above.

**Do not run `podman login` to fix a denial.** It writes the credential you pass
to `$XDG_RUNTIME_DIR/containers/auth.json`, which podman reads **first**. A login
with a fine-grained PAT therefore overwrites a working credential and guarantees
the denial. On 2026-08-23 a session did exactly this, then read the resulting
403 as proof that the box had no packages access.

**podman prints the error code, not the message.** Both 403 rows above reach you
as `reading manifest 0.20.0 in ghcr.io/...: denied`, so the terminal cannot
separate a scope-less token from no token. Read the manifest directly to see
which:

```bash
set -a; . ~/.config/0x58/credentials.env; set +a
T=$(curl -s -u "arbeitandy:$GHCR_TOKEN" \
  "https://ghcr.io/token?service=ghcr.io&scope=repository:iden2-com/mirror/vault:pull" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" \
  https://ghcr.io/v2/iden2-com/mirror/vault/manifests/1.20.4      # expect 200
```

So pull:

```bash
docker pull ghcr.io/iden2-com/mirror/postgres:17.2
```

If the pull fails, read the auth files in precedence order before you change
anything:

```bash
. ~/.local/share/kind-shims/env.sh
for f in "$XDG_RUNTIME_DIR/containers/auth.json" ~/.config/containers/auth.json \
         ~/.docker/config.json; do
    printf '%s -> ' "$f"; [ -r "$f" ] && wc -c < "$f" || echo UNREADABLE
done
podman login --get-login ghcr.io          # expect: arbeitandy
```

**Open question: what the sandbox sees.** On 2026-08-23 a sandboxed session got
`denied` while an unsandboxed `podman pull` of the same tag succeeded, before any
fix. The sandbox is therefore the difference, and I did not prove the mechanism.
Claude Code treats `~/.docker/config.json` as a credential file and has no
awareness of `containers/auth.json`, which points at masking. I did not measure
it. If you meet this, run the loop above **inside** the sandbox and record which
files are readable.

The upstream fallback many Dockerfiles document (e.g. the did-sync init container
taking `BASE_IMAGE=hashicorp/vault:1.20.4`) still works and is still a reasonable
degraded path. It is no longer the expected one.

**What the token can and cannot do.** Scope is `read:packages`, verified against
`x-oauth-scopes` rather than assumed. It cannot read a repository, cannot write a
package, and cannot act anywhere else. It lives in
`~/.config/0x58/credentials.env` as `GHCR_TOKEN`, which agents **can** read —
a deliberate choice, not an oversight: this box puts its weight on source control
and a proven rebuild, not on hiding a read-only scope. Do not treat finding it
there as a vulnerability report.

The packages are `internal` visibility, which is why a token is needed at all.
Making `mirror/*` public would remove the need entirely for most of them, but
Andy declined it on 2026-08-23: the mirrors stay internal for now. Two things to
carry into that conversation if it reopens. Scope any flip to the images that
mirror open-source upstreams; `mirror/dhi-*` are Docker Hardened Images, a paid
product, so their visibility is a licensing question rather than a config one.

**A denial is per-token, never per-package.** One bad credential denies **every**
`ghcr.io/iden2-com/*` ref at once. So do not read a single failing image as a
problem with that image, and do not read a passing stack as proof that ghcr works.

**What in `dev/kind` needs ghcr.** Two things: the warm node image
`mirror/kind-node-warm:<key>`, which `task kind:up` pulls before anything else
runs, and the three `mirror/waltid-*` images. The helm-deployed infra does not —
redis comes from `docker.io/bitnami`, postgres from `mirror.gcr.io`, keycloak from
`quay.io`, vault from `docker.io/hashicorp`, and every iden2 service builds
locally as `docker.io/iden2-kind/*:dev`.

Outside `dev/kind`, `docker-compose/infra.yml` and `synth-obs.yml` also pull
`mirror/vault`, `mirror/waltid-wallet-api` and
`mirror/opentelemetry-collector-contrib`, and `.github/actions/docker-bootstrap`
pulls `mirror/buildkit`.

I got this wrong on 2026-08-23 and it reached `main`. I wrote that walt.id was the
only ghcr reference in `dev/kind`, having grepped the charts and missed
`kind-node-warm` in the Taskfile. The kindtest session then measured what I should
have: `mirror/postgres`, `mirror/vault` and `mirror/buildkit` were denied too.

## kind

kind needs the podman provider explicitly, on top of the shim above:

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
```

Rootless podman could not bind privileged host ports until **2026-08-04**, when
`net.ipv4.ip_unprivileged_port_start = 0` was applied to the devbox — so a
cluster config mapping 80/443 now works as written. Verify rather than assume,
since this is devbox-only and deliberately NOT set on the k8s node (low ports
there would also mean port 53, a DNS-spoofing position on the box that runs
untrusted work):

```bash
cat /proc/sys/net/ipv4/ip_unprivileged_port_start    # 0 = low ports allowed
```

If it reads `1024`, fall back to unprivileged ports — and copy the config out and
edit the copy rather than mutating the repo's.

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

**The toolbox image now exists — use it, do not rebuild it.** As of 2026-08-04
`localhost/0x58-toolbox:latest` carries `socat`, `kubectl`, `helm`, `git`, `jq`
and `psql`, with the tools verified at build time so a missing `helm` fails the
build rather than minute 28 of an e2e run.

```bash
~/src/public/0x58/dev/nodes/toolbox/build           # build if missing
~/src/public/0x58/dev/nodes/toolbox/build --force   # after a version bump
```

Measured: **12.3s** for the old install-every-time path against **0.5s** ready,
about 26x — but that is per container **start**. It is decisive in the one-shot
pattern an agent falls into naturally (100 invocations is 20 minutes) and nearly
worthless if you keep one container alive. **Keeping one alive is the larger
win**; the image just makes both patterns cheap.

Host packages do not help a container — a fresh container starts from nothing,
and that trap has sprung more than once. If you catch yourself `apt-get
install`-ing this list, the image is missing: build it rather than working
around it.

## Tear down when the work is done — this is your job, not the human's

**Order matters: tests green → PR/issue updated → then tear down.** Not before.
Review feedback routinely needs one more run against the same cluster, and
rebuilding it costs far more than keeping it for another ten minutes. Once the
report is posted, destroy it without being asked.

A cluster left running is not free on this box. Measured on 2026-08-04, teardown
returned **1.6 GB of RAM and 8 GB of disk** on a 4 GB machine — worth reclaiming
on its own terms.

Correcting this paragraph's original claim of "no swap": the box carries **4.5 GB**
(a 496 MB Linode partition plus a 4 GB swapfile), and on 2026-08-04 the swapfile
was at **0 B used**. So OOM is not the live risk it was written up as, and if
something is slow, memory is the wrong place to look first.

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

- **Pulls do not traverse the sandbox's network path.**
  `docker.io/library/alpine:3.20` pulled in-session at a time when `docker.io`
  was blocked for the agent's own sockets — the service fetches on your behalf,
  from outside the session netns. Since the domain allowlist was removed on
  2026-08-05 this no longer *strands* anything, but it still means container
  traffic is invisible to the sandbox and is not shaped by it.
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
