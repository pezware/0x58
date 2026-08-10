# ~/.kube

## Structure

```
configs/                    # Per-environment kubeconfig files (one context each)
  gke-<env>/config          # GKE via Connect Gateway (fleet memberships)
  eks-<env>/config          # AWS EKS clusters
  kind-<name>/config        # Kind clusters (on the devbox)
  .window-overlays/         # Auto-managed per-kitty-window current-context
config                      # Default kubeconfig (not used by our setup)
```

## How it works

All configs are merged into a single `KUBECONFIG` at shell startup via `~/.bash/kubectl-context.bash`.
In kitty terminal, each window/panel gets its own active context through a per-window overlay file.
Default context for new windows: `gke-stg-ro` (configurable via `KUBE_DEFAULT_CONTEXT`).

`KUBECONFIG` is built by globbing `configs/*/`, so removing a cluster is just
removing its directory — there is no list to keep in sync. The corollary bit us
once: a stale `orbstack/` directory kept a dead context in the merge list long
after OrbStack was gone.

## Commands

| Command | Description |
|---|---|
| `kube-use <ctx>` | Switch context (per-window in kitty) |
| `kube-list` | List all contexts and config directories |
| `kube-current` | Show active context and config sources |
| `kube-refresh` | Rebuild KUBECONFIG after adding/removing configs |

## Setup commands

Setup commands write to `configs/<type>-<env>/config`, create a short context alias
(`gke-<env>`, `eks-<env>`, etc.), and call `kube-refresh` automatically.

| Command | Example |
|---|---|
| `kube-setup-gke <env> <cluster> [location] [project]` | `kube-setup-gke staging iden2-staging-gke` |
| `kube-setup-eks <env> <cluster> [region]` | `kube-setup-eks dev my-cluster eu-central-2` |
| `kube-setup-kind <name>` | `kube-setup-kind iden2-dev` |

## GKE defaults

- Location: `europe-west4`
- Project: `iden2-ops-<env>`

## Security

### What lives where

| Config | Auth mechanism | Secrets in kubeconfig? |
|---|---|---|
| GKE | Exec plugin (`gke-gcloud-auth-plugin`) | No — tokens fetched on demand |
| EKS | Exec plugin (`aws eks get-token`) | No — tokens fetched on demand |
| Kind | Embedded client certificate + key | Yes — static TLS credentials |
| OrbStack | Embedded client certificate + key | Yes — static TLS credentials |

### Credential locations

- **GKE/gcloud**: `~/.config/gcloud/credentials.db` (OAuth refresh token), `access_tokens.db` (short-lived)
- **AWS/EKS**: Managed by AWS CLI profiles (`~/.aws/`)
- **Kind/OrbStack**: Client cert and key embedded directly in the kubeconfig files

### Protections in place

- **FileVault**: On (full-disk encryption at rest)
- **File permissions**: All kubeconfig files are `600` (owner-only read/write)
- **No long-lived tokens**: GKE and EKS use exec-based auth with short-lived tokens
- **Per-window isolation**: Context switches don't leak across kitty panels

### Notes

GKE kubeconfigs contain no secrets — only the cluster endpoint and exec plugin reference.
The actual OAuth refresh token in `~/.config/gcloud/credentials.db` cannot be moved to
macOS Keychain (gcloud does not support it). FileVault + file permissions are the
primary defense for local credentials.
