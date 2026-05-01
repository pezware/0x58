# Secretive Key Rotation & Recovery

How to rotate or recover Secretive (Secure Enclave) SSH keys for GitHub + GitLab,
covering both planned rotation and OS-update-induced wipes.

## When to rotate

| Trigger | What's wrong | Action |
|---|---|---|
| Planned rotation | Annual hygiene | Full rotation (this doc) |
| `ssh-add -L` returns no keys after OS update | SE keys orphaned | Full rotation (after [Touch ID check](#recovery-from-os-update-wipe)) |
| Touch ID prompts disappeared | Biometric catacomb wiped | [Re-enroll fingerprints first](#recovery-from-os-update-wipe), then rotate |
| Suspected key compromise | Security incident | Full rotation + revoke old keys server-side |

## Architecture (one Secretive key per identity)

This setup uses **two SE keys**, one per identity, because:

1. GitHub enforces **global key uniqueness** — one SSH key can only be registered as auth/signing on one GitHub account. Sharing one key across `arbeitandy` + `achtungandy` is server-side blocked.
2. Per-identity keys give per-identity audit isolation: a compromise of the iden2 key doesn't touch pezware commits and vice versa.

| Identity | Email | Secretive key name | Used for |
|---|---|---|---|
| iden2 (work) | `andy@iden2.com` | e.g. `andy@iden2.com` | github.com/arbeitandy + default git signing |
| pezware (personal) | `andy@pezware.com` | e.g. `andy@pezware.com` | github.com/achtungandy + repos in `~/src/public/` |

The local git layout uses `includeIf` to switch identity per directory:

- `~/.gitconfig` → iden2 identity (default)
- `~/.config/git/personal` → loaded for `gitdir:~/src/public/.` → pezware identity

## Pre-flight checks

Run these before any rotation to surface auth issues early:

```bash
# 1. Both GitHub accounts must have admin:public_key + admin:ssh_signing_key scopes
gh auth status
# If achtungandy is missing scopes, refresh (interactive — opens browser):
gh auth switch -h github.com -u achtungandy
gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key
gh auth switch -h github.com -u arbeitandy

# 2. Verify Secretive agent is responding
SSH_AUTH_SOCK="$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh" \
  ssh-add -l

# 3. Verify Touch ID actually works (silent failure = catacomb wipe — see Recovery)
sudo -k && sudo true  # should prompt Touch ID, not fall through to password
```

Skip glab — its OAuth2 default in v1.93+ is broken on first login and the
PAT alternative defeats the on-disk-secrets-free design. Use the GitLab web
UI for the GitLab step.

## Rotation procedure

### Step 1 — Create new Secretive keys (GUI)

For each identity:

1. Open **Secretive.app** (already running in menu bar)
2. Click **`+`**
3. Fill in:
   - **Name:** `andy@iden2.com` (or `andy@pezware.com`) — this becomes the SSH key comment
   - **Protection Level:** `Current Biometrics`
   - **Key Type:** `ecdsa-256`
4. Click **Create** → Touch ID prompt → tap

Verify both keys are live:

```bash
ssh-add -L
# Expected: 2 lines, comments matching the names you chose
```

### Step 2 — Upload to GitHub (both accounts)

```bash
HOSTNAME_SHORT="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
NEW_TITLE="secretive-${HOSTNAME_SHORT}-$(date +%Y%m)"

IDEN2_PUBKEY="$(ssh-add -L | grep ' andy@iden2.com$')"
PEZWARE_PUBKEY="$(ssh-add -L | grep ' andy@pezware.com$')"

# arbeitandy: iden2 key as auth + signing
gh auth switch -h github.com -u arbeitandy
echo "$IDEN2_PUBKEY" | gh ssh-key add --title "$NEW_TITLE" --type authentication -
echo "$IDEN2_PUBKEY" | gh ssh-key add --title "$NEW_TITLE" --type signing -

# achtungandy: pezware key as auth + signing
gh auth switch -h github.com -u achtungandy
echo "$PEZWARE_PUBKEY" | gh ssh-key add --title "$NEW_TITLE" --type authentication -
echo "$PEZWARE_PUBKEY" | gh ssh-key add --title "$NEW_TITLE" --type signing -

gh auth switch -h github.com -u arbeitandy
```

**Add-then-delete order is intentional**: never have a window where you can't push.

After upload succeeds, delete the now-orphaned old keys (run for each account):

```bash
# Per account, list keys → identify old ones by title or fingerprint → delete by id
gh api /user/keys --jq '.[] | "\(.id)\t\(.title)"'
gh api /user/ssh_signing_keys --jq '.[] | "\(.id)\t\(.title)"'

# Then for each stale id (replace 12345):
gh api -X DELETE /user/keys/12345
gh api -X DELETE /user/ssh_signing_keys/12345
```

Keep Yubikey keys (`andy-yb-*`, `andy-linux-yb`) — those are separate hardware
tokens and survive any SE/macOS event.

### Step 3 — Upload to GitLab (web UI)

Open <https://gitlab.com/-/user_settings/ssh_keys>

For each key, click **Add new key**:

- **Title:** `secretive-${HOSTNAME_SHORT}-${YYYYMM}-${identity}`
- **Usage type:** `Authentication & Signing`
- **Key:** paste from `ssh-add -L`

GitLab allows multiple keys on one account (it doesn't enforce GitHub's
uniqueness rule), so both keys go on your one GitLab account. For the
**Verified** badge on `andy@pezware.com` commits, that email must also be
added as a verified email on the GitLab account (Profile → Emails).

Optionally delete old `secretive-*` keys at the same page.

### Step 4 — Update local git config

```bash
IDEN2_PUBKEY="$(ssh-add -L | grep ' andy@iden2.com$')"
PEZWARE_PUBKEY="$(ssh-add -L | grep ' andy@pezware.com$')"

# Global default — iden2
git config --global user.signingkey "key::$IDEN2_PUBKEY"

# Per-directory override for ~/src/public/* — pezware
# (Done via ~/.config/git/personal — restored from this repo by inventory.sh)
cat > ~/.config/git/personal <<EOF
[user]
	email = andy@pezware.com
	signingkey = key::$PEZWARE_PUBKEY
EOF

# Strict 1:1 allowed_signers (each email → only its own key)
cat > ~/.config/git/allowed_signers <<EOF
andy@iden2.com $IDEN2_PUBKEY
andy@pezware.com $PEZWARE_PUBKEY
EOF

# Sync into the repo so it's reproducible from inventory.sh
bash macos/inventory.sh   # picks up ~/.config/git/personal + allowed_signers
```

### Step 5 — Verify end-to-end

```bash
# SSH auth to both providers
ssh -T git@github.com   # should greet you as arbeitandy (uses iden2 key)
ssh -T git@gitlab.com   # should greet you (uses iden2 key by default)

# Local commit signing (default identity, iden2)
cd /tmp && git init verify-sign && cd verify-sign
git commit --allow-empty -m "test signing"
git log -1 --show-signature   # expect: Good "git" signature for andy@iden2.com

# Per-directory pezware identity (in ~/src/public/*)
cd ~/src/public/0x58
git config user.email     # should be andy@pezware.com
git commit --allow-empty -m "test pezware signing"
git log -1 --show-signature   # expect: Good "git" signature for andy@pezware.com
```

## Recovery from OS update wipe

After a macOS update, all of these can occur together:

- `ssh-add -L` returns no identities (Secretive keys "gone")
- Touch ID prompts disappear (sudo silently falls through to password)
- Secretive's Create dialog shows "Authentication failure" with greyed Create button

**Single root cause** in 99% of cases: the macOS update wiped your biometric
template database (catacomb). The SE keys aren't gone — they're tied to the
old catacomb's identity hash, which no longer exists.

### Diagnose first (don't reboot blindly)

```bash
bioutil -c
```

- `0 biometric template(s)` → catacomb wiped → re-enroll fingerprints
- `1+ biometric template(s)` but Touch ID still silent → check
  `log show --predicate 'process == "biometrickitd"' --last 5m | grep -iE 'error|fail'`
  for runtime cache issues. A reboot usually fixes those.

### Re-enroll fingerprints

System Settings → Touch ID & Password → Add a Fingerprint. Authenticate with
your account password. This rebuilds the catacomb against your current user UUID.

After enrollment, verify:

```bash
bioutil -c                          # should now show 1+ templates
sudo -k && sudo true && echo OK     # should prompt Touch ID this time
```

### Then rotate

Old SE keys cannot be recovered (they were tied to the old catacomb).
Run the [rotation procedure](#rotation-procedure) from Step 1.

## Notes

- **Secretive's GUI rename doesn't refresh the agent's SSH comment immediately.**
  The comment in `ssh-add -L` may stay stale until the agent restarts. The key
  bytes/fingerprint are unchanged either way — git matches by bytes, not comment.
- **Orphan `*.pub` files** in
  `~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/PublicKeys/`
  accumulate. Safe to delete the ones whose fingerprints don't match any current
  Secretive key. Cosmetic only — Secretive renders these in its UI.
- **Old server-side keys** with no usable private half are harmless but should be
  cleaned up for hygiene (Step 2 cleanup, plus GitLab web UI).
- **Yubikey keys** are independent of all of this. The `andy-yb-*` and
  `andy-linux-yb` keys live on the YubiKey hardware and survive any
  macOS/Secretive event.
