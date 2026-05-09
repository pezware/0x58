# GCP Tailscale Exit Node

On-demand Spot e2-micro VM (`pezware-tres`) that joins your tailnet as an exit node.
No open ports — Tailscale SSH only. Costs ~$0.0018/hr while running, ~$0.40/mo idle (disk).

## Bootstrap (one-time)

```bash
# 1. Init and apply — VM is created stopped
terraform init
terraform apply

# 2. Add your Tailscale auth key (reusable + pre-authorized) to Secret Manager
printf '%s' 'tskey-auth-...' | gcloud secrets versions add tailscale-exit-auth-key \
  --project=$(terraform output -raw project_id) --data-file=-

# 3. Start the VM — startup script will authenticate Tailscale on first boot
./ts-exit start

# 4. Approve the exit node in the Tailscale admin console
#    https://login.tailscale.com/admin/machines
#    pezware-tres → ⋮ → Edit route settings → Use as exit node
```

## Daily use

```bash
./ts-exit start    # boot pezware-tres (~60s to appear in tailnet)
./ts-exit stop     # shut it down
./ts-exit status   # RUNNING / TERMINATED
./ts-exit ssh      # tailscale ssh pezware-tres
```

On your client device, select `pezware-tres` as the exit node in the Tailscale app.

## TODO

- [ ] Collapse to a single `main.tf` (current 5-file split is over-engineered for a personal tool)
- [ ] Switch to Tailscale OAuth client — eliminates the manual auth key step and admin console approval
