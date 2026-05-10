# Tailscale Exit Nodes

On-demand Tailscale exit nodes across multiple clouds. Pick a cloud, run terraform, route your traffic.

## Layout

```
dev/exit-node/
├── ts-exit         # dispatcher: ./ts-exit --cloud=gcp|linode <cmd>
├── gcp/            # GCP e2-micro spot VM — currently DESTROYED (kept for re-activation)
└── linode/         # Linode Nanode 1 GB — currently ACTIVE
```

## Active cloud: Linode

Default for the dispatcher. See [`linode/README.md`](linode/README.md) for setup and daily commands.

```bash
./ts-exit apply   # one-time provision
./ts-exit start   # boot the VM
./ts-exit stop    # power off (note: doesn't save money on Linode)
./ts-exit ssh     # tailscale ssh pezware-cuatro
```

## Inactive cloud: GCP

Code preserved for re-activation. Original spot VM was preempted 2026-05-08; we destroyed the infra in favor of Linode's flat pricing.

To re-activate:

```bash
gcloud auth application-default login   # ADC for terraform (separate from `gcloud auth login`)
cd gcp && terraform apply
# then update GCP Secret Manager with the current tagged Tailscale auth key:
security find-generic-password -s tailscale-exit-authkey -a "$USER" -w \
  | gcloud secrets versions add tailscale-exit-auth-key \
      --project=$(terraform output -raw project_id) --data-file=-
```

## When to use which

|           | Linode Nanode               | GCP spot e2-micro          |
|-----------|-----------------------------|----------------------------|
| Stability | No preemption               | Preempted ~weekly          |
| Cost      | $5/mo flat, 1 TB egress     | ~$1.30/mo when running, per-GB egress |
| Idle savings | None (billed monthly)    | ~$0.40/mo when stopped     |

Rule of thumb: **Linode if you want it always available; GCP if you only use it ad-hoc and tolerate the occasional 60-second restart**.

## Secrets

Both clouds pull secrets from macOS Keychain — nothing on disk:

- `linode-pat` — Linode API Personal Access Token (Linodes R/W, Firewalls R/W, Images R)
- `tailscale-exit-authkey` — Tailscale reusable + pre-authorized auth key, **tagged `tag:exit-node`** (shared between clouds)
- (GCP also needs ADC: `gcloud auth application-default login` — separate from `gcloud auth login`, separate file)

## Tailscale ACL recipe (zero-touch onboarding)

For new exit-node machines to fully self-onboard with no manual admin-console clicks, the tailnet ACL needs three pieces. Edit at https://login.tailscale.com/admin/acls/file:

```jsonc
{
  // Declares tag:exit-node as a real tag. Required before any auth key can use it.
  "tagOwners": {
    "tag:exit-node": ["autogroup:admin"]
  },

  // Auto-approves exit-node advertisement for any device wearing tag:exit-node.
  // Without this, every new machine needs a manual click in admin → machines.
  "autoApprovers": {
    "exitNode": ["tag:exit-node"]
  },

  // Tag-owned devices have no SSH access by default. Without this, tailscale ssh
  // returns "tailnet policy does not permit you to SSH to this node".
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:admin"],
      "dst": ["tag:exit-node"],
      "users": ["root", "arbeitandy"]
    }
  ]
}
```

When generating the auth key (https://login.tailscale.com/admin/settings/keys), set:
**Reusable: ON · Pre-approved: ON · Tags: ON → tag:exit-node · Expiration: ≤90 days**.

## Gotchas worth remembering

- **Linode bills the Nanode monthly regardless of power state.** `./ts-exit stop` does *not* save money — it's just a power-off. Real cost savings require `./ts-exit destroy`. (Counter-intuitive for AWS/GCP-trained intuition where stop ≈ free.)
- **Tag-owned Tailscale devices reject SSH by default.** When migrating from a user-owned to a tag-owned device, your `tailscale ssh` will start failing silently with a policy error — you need an explicit `ssh` ACL rule (see recipe above). Easy to mistake for a network-level firewall problem.
- **GCP spot VMs get preempted on GCP's schedule, not yours.** `provisioning_model = "SPOT"` saves ~70% but the VM disappears every ~1-14 days. To diagnose post-mortem without enabling Cloud Logging API, use `gcloud compute operations list --filter="targetLink~<instance> AND insertTime>YYYY-MM-DD"` — the operations API is free and shows preemption events directly.
- **`templatefile()` doesn't see `path.module`.** Inside a templated file, only the explicit `vars` map is in scope. To embed a sibling file's content, read it in the calling `.tf` and pass as a var: `bootstrap_script = file("${path.module}/bootstrap.sh")`.
