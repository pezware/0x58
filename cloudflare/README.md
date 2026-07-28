# cloudflare — short bootstrap URLs

Serves [`linux/start.sh`](../linux/start.sh) at `https://m.pezware.com/linux-start.sh`
so a bare machine can be bootstrapped with one command.

```bash
bash -c "$(curl -fsSL https://m.pezware.com/linux-start.sh)"
```

## Why a Worker and not a CNAME

A CNAME cannot serve this, for three independent reasons:

1. **Virtual hosting** — `raw.githubusercontent.com` serves on the `Host` header
   and rejects one it does not own.
2. **TLS** — the cert presented would be GitHub's, not `pezware.com`'s, so `curl`
   aborts on the mismatch before any bytes arrive.
3. **Paths** — DNS maps names to addresses; it cannot rewrite `/linux-start.sh`
   into `/pezware/0x58/main/linux/start.sh`.

The Worker terminates TLS on our hostname, maps the short path, and proxies.

## Setup

1. **DNS** (Cloudflare dashboard → pezware.com → DNS). Worker routes require a
   record to exist for the hostname and to be **proxied**. Nothing ever connects
   to it — Cloudflare short-circuits to the Worker at the edge — so use a discard
   address:

   | Type | Name | Content | Proxy |
   |---|---|---|---|
   | AAAA | `m` | `100::` | Proxied (orange) |

   Universal SSL covers one level of subdomain, so `m.pezware.com` gets a cert
   automatically. No certificate work needed.

2. **Deploy** (wrangler is already in `dotfiles/mise/config.toml`):

   ```bash
   cd cloudflare
   wrangler login          # one-time, opens a browser
   wrangler deploy
   ```

3. **Verify** — check it is the script and not an error page before piping it
   anywhere:

   ```bash
   curl -fsSL https://m.pezware.com/linux-start.sh | head -20
   curl -sI https://m.pezware.com/linux-start.sh | grep -Ei 'content-type|x-source'
   ```

## Pinning

`REF` in [`worker.js`](worker.js) selects what gets served. It is `main` today,
which means the one-liner runs whatever landed most recently. For anything
beyond a personal box, cut a tag and pin to it — `curl | bash` against a moving
branch means the command you ran last month is not the command you run today.

## Adding another script

Add one line to `ROUTES` in `worker.js` and redeploy. The map is an explicit
allowlist on purpose: without it this Worker becomes an open proxy for arbitrary
repository contents.
