# Sealed secrets on the devbox

A sandboxed session on the devbox runs as your uid, so it can read any file you
can. A key in `~/.config/0x58/credentials.env` or `~/.ssh` is therefore a key
every session holds. Sealing moves the key where that uid cannot read it, and
hands sessions a unix socket that *uses* the key instead.

| secret | sealed as | sessions get |
|---|---|---|
| xAI key (smallscreen-books) | `/etc/credstore.encrypted/xai` | `/run/xai-broker/xai.sock` |
| Linode PAT (scoped) | `/etc/credstore.encrypted/linode` | `/run/linode-broker/linode.sock` |
| Tailscale OAuth client (`tag:k8s`) | `/etc/credstore.encrypted/tailscale` | `/run/tailscale-broker/tailscale.sock` |
| ssh signing keys | `/etc/credstore.encrypted/ssh-<name>` | `/run/ssh-agent-<user>/agent.sock` |

`systemd-creds encrypt --with-key=host` seals each one against
`/var/lib/systemd/credential.secret` (root, 0600). PID 1 decrypts it into a
tmpfs for one unit only. A sandboxed session cannot read either file and cannot
sudo under `no_new_privs` ([`../confinement-design.md`](../confinement-design.md)).

## How a route works

`secret-broker@<route>.service` runs one broker per key. The broker listens on
`/run/<route>-broker/<route>.sock`, forwards one path to one upstream, and
replaces the credential header the client sent with the real one. Every call
leaves one journal line with the caller's uid and pid, and never a header or a
body.

A route file in [`routes/`](routes/) configures it:

| variable | meaning | default |
|---|---|---|
| `BROKER_UPSTREAM` | the `https://` origin to forward to | required |
| `BROKER_PATH` | what to forward: `/v1/` is a subtree, `/a/b` one path | required |
| `BROKER_HEADER` | the header that carries the credential | `Authorization` |
| `BROKER_HEADER_PREFIX` | text before the key; set it empty for `x-api-key` | `Bearer ` |
| `BROKER_KEY_PREFIX` | refuse to seal or start with a key not starting so | none |
| `BROKER_AUTH` | `static`, or `oauth2` for client credentials | `static` |
| `BROKER_TOKEN_URL` | the token endpoint, for `oauth2` | — |
| `BROKER_RPM` | requests per minute before a 429 | `60` |
| `BROKER_ESCROW_ITEM` | the Mac Keychain item `devbox-keys` seals from | — |

With `oauth2`, the sealed credential is `<client_id>:<client_secret>`. The
broker trades it for access tokens and sends only those upstream.

## Adding a key

1. **Scope it at the provider first.** The broker stops a session from reading
   the key. It does not stop a session from using it. Give the key the least
   access the job needs, and set a spend limit where the provider has one.
2. **Write `routes/<route>.env`.** Keep `BROKER_PATH` as narrow as the job
   allows, and set `BROKER_KEY_PREFIX` when keys have a known prefix.
3. **Escrow it on the Mac,** through stdin so the key never reaches argv:
   ```bash
   printf 'add-generic-password -U -s <item> -a %s -w %s\n' "$USER" "$(pbpaste)" | security -i
   ```
4. **Test the unit before the box sees it.** From the Mac:
   `linux/sealed-secrets-test`. Add a check for the new route: a fake key that
   the upstream refuses proves the broker injected it.
5. **Seal it:** `dev/nodes/devbox-keys restore`. Then add the route to the
   broker loop in `dev/nodes/devbox-smoketest`.

Callers use the socket and send any placeholder credential:

```bash
curl --unix-socket /run/<route>-broker/<route>.sock http://<route>/<path>
```

A tool that speaks only TCP gets a loopback bridge for its lifetime, as
`ts-node` does for Terraform:
`socat TCP-LISTEN:<port>,bind=127.0.0.1,fork UNIX-CONNECT:<socket>`.

**When a key does not fit a route:** request signing (AWS SigV4), a registry
token exchange, or a tool that insists on reading a file. Leave that key in
`credentials.env`, scope it hard, and record why in
[`../../dev/nodes/README.md`](../../dev/nodes/README.md).

## ssh keys

ssh does not speak HTTP, so its keys get an agent instead of a route. The
design is the same: sealed at rest, and a socket for sessions.
[`../ssh-agent/install`](../ssh-agent/install) seals a key as `ssh-<name>`.
`devbox-ssh-agent-load@<user>` imports every `ssh-*` credential as root and adds
it to `devbox-ssh-agent@<user>`. Adding an ssh key is one more `--seal`, with no
unit change.

## What sealing does not protect

- **Use.** A session can still spend the key or sign with it while the box is
  up. Provider-side scope and the broker's request budget bound that.
- **Your own login.** `arbeitandy` has `NOPASSWD:ALL`. Root sealing holds
  against sandboxed sessions, which cannot sudo. It does not hold against an
  agent that persists into your unsandboxed shell.
- **The host.** There is no TPM, so the host key rests on file permissions.
  A disk image or a host-root compromise defeats it.

On the Mac, [`install-macos`](install-macos) runs the xai route under launchd with
the key in the login Keychain. The Mac has no sandbox, so there the broker keeps
keys out of env vars and child processes but is not a boundary.
