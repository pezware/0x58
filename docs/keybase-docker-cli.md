# Keybase CLI via Docker

Run Keybase CLI without installing the macOS GUI app or background services.

## Prerequisites

- Docker
- GPG-encrypted paper key at `~/.keybase-paper-key.gpg`

## Setup (one-time)

Generate a paper key from an authenticated Keybase session, then encrypt it locally:

```bash
echo "your paper key words here" | gpg --encrypt --recipient <YOUR_KEY_ID> --output ~/.keybase-paper-key.gpg
```

## Quick Start

```bash
# Decrypt paper key and login in one shot
docker run --rm -it \
  -v keybase_data:/home/keybase/.config/keybase \
  keybaseio/client:stable \
  keybase login --paperkey "$(gpg --decrypt ~/.keybase-paper-key.gpg 2>/dev/null)"
```

## Interactive Session

For chatting or multiple commands, start a session:

```bash
docker run --rm -it \
  -v keybase_data:/home/keybase/.config/keybase \
  keybaseio/client:stable bash
```

Then inside:

```bash
keybase login --paperkey "DECRYPTED_PAPER_KEY"
# or if already authenticated from a previous run:
keybase chat send <user> "message"
```

## Common Commands

```bash
# Chat
keybase chat send <user> "message"
keybase chat read <user>

# Identity
keybase follow <user>
keybase id <user>

# Crypto
keybase encrypt <user> -m "secret"
keybase decrypt
keybase sign -m "message"

# Device management
keybase paperkey           # generate a new paper key
keybase device list        # list authorized devices
```

## Cleanup

```bash
# Remove Docker volume when done with Keybase entirely
docker volume rm keybase_data
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `dial unix keybased.sock: no such file or directory` | Run `keybase service &` first, wait 2 seconds |
| Platform mismatch warning (arm64 vs amd64) | Works via emulation, just slower. No arm64 image available. |
| Paper key not working | Verify with `gpg --decrypt ~/.keybase-paper-key.gpg` that it decrypts correctly |

## First-Time Setup via GPG Key (hard way)

If you don't have a paper key yet and need to bootstrap using your GPG private key,
see the full GPG setup below. Once logged in, immediately run `keybase paperkey` and
encrypt it for future use.

<details>
<summary>GPG key bootstrap (click to expand)</summary>

```bash
# Export your GPG secret key
gpg --export-secret-keys <YOUR_KEY_ID> > /tmp/keybase-key.gpg

# Launch container as root (needed to fix permissions)
docker run --rm -it --user root --entrypoint /bin/bash \
  -v keybase_data:/home/keybase/.config/keybase \
  -v /tmp/keybase-key.gpg:/tmp/key.gpg \
  keybaseio/client:stable

# Inside the container (as root):
mkdir -m 700 /tmp/gnupg
gpg --homedir /tmp/gnupg --batch --pinentry-mode loopback --import /tmp/key.gpg
cp -r /tmp/gnupg /home/keybase/.gnupg
chown -R keybase:keybase /home/keybase/.gnupg /home/keybase/.config
chmod 700 /home/keybase/.gnupg

# Set up GPG loopback pinentry (avoids pinentry dialog failures)
su -s /bin/bash keybase -c 'echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf'
su -s /bin/bash keybase -c 'echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf'
su -s /bin/bash keybase -c "gpgconf --kill gpg-agent"

# Start keybase service and switch to keybase user
su -s /bin/bash keybase -c "keybase service &"
sleep 2
passwd keybase  # set a temp password
su -s /bin/bash keybase

# Login, then immediately generate a paper key for future use
keybase login
keybase paperkey
```

When prompted for GPG usage, choose option **(1)** — let Keybase use GPG commands to sign.

After login, encrypt your paper key locally:

```bash
# Back on your host machine
echo "your paper key words" | gpg --encrypt --recipient <YOUR_KEY_ID> --output ~/.keybase-paper-key.gpg
rm /tmp/keybase-key.gpg
```

</details>
