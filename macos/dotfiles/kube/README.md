# ~/.kube

## Structure

```
configs/                    # Per-environment kubeconfig files (one context each)
  gke-<env>/config          # GKE via Connect Gateway (fleet memberships)
  eks-<env>/config          # AWS EKS clusters
  kind-<name>/config        # Kind clusters (the devbox's only contexts)
  .window-overlays/         # Auto-managed per-pane current-context
config                      # Default kubeconfig (not used by our setup)
```

## Which machine has what

Not the same set, and deliberately so.

| | Mac | devbox |
|---|---|---|
| Contexts | `gke-*`, `eks-*` (tracked in the repo, installed by `restore.sh`) | `kind-*` only, imported from the local clusters |
| Auth | exec plugin — `gke-gcloud-auth-plugin`, `aws eks get-token` | client cert embedded by kind |

The devbox has neither exec plugin installed and is not meant to. `restore.sh`
used to copy the cloud configs there anyway, so `kube-list` advertised two
clusters that could not work in principle — not "needs a login", but "no such
binary", discovered only when a command finally ran against a context the prompt
had been claiming for weeks. The install is now macOS-gated and
`prune_retired_state` removes the ones already placed.

## How it works

All configs are merged into a single `KUBECONFIG` at shell startup via `~/.bash/kubectl-context.bash`.
In kitty terminal, each window/panel gets its own active context through a per-window overlay file.

`KUBECONFIG` is built by globbing `configs/*/`, so removing a cluster is just
removing its directory — there is no list to keep in sync. The corollary bit us
once: a stale `orbstack/` directory kept a dead context in the merge list long
after OrbStack was gone.

### The current context is never invented

`KUBE_DEFAULT_CONTEXT` (default `gke-stg-ro`) is **validated before it is used**.
A new pane pins it only if some installed config actually defines it; otherwise
the overlay pins nothing and the merge falls through to a config that does. With
no configs at all, there is no context and the prompt shows nothing — an empty
prompt segment is the honest report, not a placeholder.

This matters because kubectl stores a dangling pointer without complaint:
`kubectl config current-context` reports a retired name perfectly happily, and
only the first real call fails with `context was not found for specified
context`. Stamping an unchecked default is what left the Mac on `orbstack` for
months after OrbStack was removed, and all 23 devbox panes on it a week after
that — on a box where it had never existed at all.

Two things keep it converged: each shell repairs its own pane's overlay at
startup if the pinned context is defined nowhere, and `kube-prune-overlays`
sweeps every other pane in one pass (`restore.sh` calls it).

## Commands

| Command | Description |
|---|---|
| `kube-use <ctx>` | Switch context (per-window in kitty) |
| `kube-list` | List contexts, and each config directory by what it defines |
| `kube-current` | Show active context and config sources; flags a dangling pin |
| `kube-refresh` | Rebuild KUBECONFIG after adding/removing configs |
| `kube-clean-overlay` | Reset this pane's overlay, keeping the context if it still resolves |
| `kube-prune-overlays` | Drop every pane overlay pinning a context nothing defines |

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

### Credential locations

- **GKE/gcloud**: `~/.config/gcloud/credentials.db` (OAuth refresh token), `access_tokens.db` (short-lived)
- **AWS/EKS**: Managed by AWS CLI profiles (`~/.aws/`)
- **Kind**: Client cert and key embedded directly in the kubeconfig files

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
