# GCP Remote Dev Box

On-demand Spot `e2-standard-8` VM (`pezware-dev`) that joins your tailnet as a
remote development environment. Built to run a heavy local kind cluster (Istio +
Gateway API) plus Go builds and an agent (Claude Code / Codex CLI). No open
ports — Tailscale SSH only.

Connect from your MacBook or phone, start an agent in `tmux`, disconnect, and
let it work. The agent CLIs handle their own phone hand-off / notifications.

## How it stays cheap

- **Spot** pricing (~70% off) with `instance_termination_action = STOP` — a
  preemption just stops the VM; both disks survive, so repos and the agent's
  checkpointed work persist.
- **Idle auto-shutdown** — the VM stops itself when nobody is connected and the
  15-min load average is low. A running agent keeps load up, so work is not cut
  short. Override with `sudo touch /run/dev-keepalive`.
- **Stop when done** — `./exit-dev stop`. While stopped you pay only for disks.

| Item | Monthly |
|------|---------|
| Boot disk 30 GB + data disk 80 GB (`pd-balanced`) | ~$11 |
| Secret Manager + GCS backup | ~$0.30 |
| **Fixed floor (VM stopped)** | **~$11** |
| Compute, Spot `e2-standard-8` (~$0.08/hr) — light ~40 hr | +$3 |
| Compute — moderate ~160 hr | +$13 |
| **Typical total** | **~$15–25/mo** |

Agent LLM API usage (Anthropic / OpenAI) is billed separately and is usually the
largest line item.

## Bootstrap (one-time)

```bash
# 1. Init and apply — the VM is created stopped, the data disk is created empty
terraform init
terraform apply

# 2. Add your Tailscale auth key (reusable + pre-authorized) to Secret Manager
printf '%s' 'tskey-auth-...' | gcloud secrets versions add exit-dev-tailscale-auth-key \
  --project=$(terraform output -raw project_id) --data-file=-

# 3. (optional) Add agent API keys for `dev-secrets` to fetch at runtime
printf '%s' 'sk-ant-...' | gcloud secrets versions add exit-dev-anthropic-api-key \
  --project=$(terraform output -raw project_id) --data-file=-

# 4. Start the VM — first boot installs the toolchain (~3-5 min)
./exit-dev start

# 5. Approve the node in the Tailscale admin console
#    https://login.tailscale.com/admin/machines
```

Then set a billing budget alert for the new project in the GCP console.

## Daily use

```bash
./exit-dev start    # boot pezware-dev
./exit-dev ssh      # tailscale ssh pezware-dev
./exit-dev status   # RUNNING / TERMINATED
./exit-dev stop     # shut it down
```

Inside the box, load secrets into the shell — they are fetched from Secret
Manager into memory, never written to disk:

```bash
export ANTHROPIC_API_KEY=$(dev-secrets exit-dev-anthropic-api-key)
gh auth login        # preferred for git — short-lived device-flow session
```

Bring up your work cluster, then start the agent in a `tmux` session so it
survives disconnects:

```bash
tmux new -s work
# clone the work repo, `task up`, launch the agent — then detach (Ctrl-b d)
```

## What's installed

`startup.sh` installs, at pinned versions: Docker (image cache on the data
disk), kind, kubectl, helm, task, Go, the Google Cloud CLI + `gke-gcloud-auth-plugin`,
Node.js, and the Claude Code / Codex CLIs. Add your own tools in the marked
block in `startup.sh` — that pinned list is the reproducible environment
definition. The script is idempotent; bump a version and reboot to upgrade.

## Layout

| File | Purpose |
|------|---------|
| `main.tf` | Project + enabled APIs |
| `network.tf` | VPC, subnet, deny-ingress / allow-egress firewall |
| `compute.tf` | Service account, data disk, VM instance |
| `secrets.tf` | Secret Manager containers (Tailscale + agent + git) |
| `storage.tf` | GCS backup bucket |
| `variables.tf` / `outputs.tf` | Inputs and post-apply instructions |
| `startup.sh` | Idempotent provisioner (runs every boot) |
| `exit-dev` | start / stop / status / ssh helper |

## Notes

- The data disk (`exit-dev-data`) is a separate resource — `terraform apply`
  changes to the VM (machine type, image) leave repos and the image cache
  intact. A full `terraform destroy` removes it; the daily GCS backup is the
  safety net.
- Repo backups rsync `~/src` to GCS daily — set the `backup_src` variable to
  change the dir (the default `src` covers `~/src/iden2` and `~/src/public`).
- This is single-tenant by design. To share with a team later, move to a
  managed dev-environment platform rather than scaling these scripts.
