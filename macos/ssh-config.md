# SSH Configuration

## Architecture

SSH authentication uses **Secretive** — an app that stores SSH keys in the Mac's Secure Enclave hardware chip. Keys never leave the hardware; the agent signs challenges on-chip.

## Agent

All hosts use Secretive's agent socket:
```
SSH_AUTH_SOCK=~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
```
This is set in both `~/.bashrc` and `~/.ssh/config` (via `identityagent`).

## GitHub

GitHub uses PKCS#11 via OpenSC — the hardware token path:
```
Host github.com
  User git
  PKCS11Provider /opt/homebrew/lib/opensc-pkcs11.so
  IdentitiesOnly no
```
This connects Secretive's hardware-backed keys to GitHub via the smart card interface.

## GitLab

GitLab uses the Secretive agent directly (no PKCS#11 layer needed):
```
Host gitlab.com
  User git
  IdentityAgent ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
  IdentitiesOnly yes
```
The explicit block is required because the `Host *` catch-all has `IdentitiesOnly yes` but no fallback to `SSH_AUTH_SOCK` — without a dedicated block, SSH skips the agent entirely for GitLab.

## Other hosts

| Host | Network | Notes |
|---|---|---|
| `pezware-uno` | Tailscale | Personal server |
| `pezware-dos` | Tailscale | Personal server |

## Global defaults (`Host *`)

- `identityagent` → Secretive socket
- `identitiesonly yes` — only offer keys from the agent
- `addkeystoagent yes`
- `setenv term=xterm-256color`

## Key dependencies

- **Secretive.app** (brew cask) — Secure Enclave SSH agent
- **opensc** (brew) — PKCS#11 provider for GitHub auth
- **Tailscale** — mesh VPN for remote host access
