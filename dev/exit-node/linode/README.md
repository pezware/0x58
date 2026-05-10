# Linode Tailscale Exit Node

On-demand Nanode 1 GB (`pezware-cuatro`) joining your tailnet as an exit node.
$5/mo flat — no spot tier on Linode, but no preemption either. 1 TB egress included.

## Setup (one-time)

### 1. Create Linode PAT

cloud.linode.com → My Profile → API Tokens → "Create a Personal Access Token":

- **Linodes**: Read/Write
- **Firewalls**: Read/Write
- **Images**: Read Only
- All others: No Access

Then store in macOS Keychain (uses prompt mode so the PAT never lands in shell history):

```bash
security add-generic-password -U \
  -s linode-pat \
  -a "$USER" \
  -j "<token-label-and-expiry>" \
  -w
# paste PAT at the prompt
```

### 2. Store Tailscale auth key in Keychain

Generate a reusable + pre-authorized key at https://login.tailscale.com/admin/settings/keys, then:

```bash
security add-generic-password -U \
  -s tailscale-exit-authkey \
  -a "$USER" \
  -j "shared with GCP exit node; rotate together" \
  -w
# paste tskey-auth-... at the prompt
```

### 3. Apply terraform

```bash
./ts-exit apply
```

The wrapper pulls both Keychain items into env vars only for the duration of the terraform call.

### 4. Approve as exit node

https://login.tailscale.com/admin/machines → `pezware-cuatro` → ⋮ → Edit route settings → Use as exit node

## Daily use

```bash
./ts-exit start    # boot via Linode API (~60s to tailnet)
./ts-exit stop     # power off (does NOT save money — Linode bills monthly)
./ts-exit status   # running / offline
./ts-exit ssh      # tailscale ssh pezware-cuatro
./ts-exit destroy  # full cleanup — only this stops billing
```

## Cost model vs GCP

|              | GCP (spot e2-micro)        | Linode (Nanode 1 GB)       |
|--------------|----------------------------|----------------------------|
| Compute      | ~$0.0018/hr                | $0.0075/hr / $5/mo flat    |
| Egress       | per-GB after 1 GB free     | 1 TB/mo included           |
| Idle (off)   | ~$0.40/mo (disk only)      | $5/mo (flat — no off-savings) |
| Preemption   | Yes, ~weekly               | None                       |

`stop` on Linode is power-off, not delete — same UX as GCP, but billing keeps running.
For real cost savings during inactive periods, use `destroy`.

## TODO

- [ ] Switch to Tailscale OAuth client — eliminates the manual auth key step (same TODO as GCP)
