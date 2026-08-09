# keymaster — Touch ID-gated keychain CLI

A small Swift CLI for putting secrets in the macOS keychain and getting them back
out behind a Touch ID prompt, so scripts can read a credential without it ever
existing as a file, an env var in a dotfile, or a shell-history entry.

```
keymaster set <key>      # read password from stdin (no echo), store it
keymaster get <key>      # retrieve — prompts for Touch ID
keymaster update <key>   # replace an existing value
keymaster delete <key>   # remove it
keymaster list           # list keys this tool has stored
```

Passwords are read from stdin via `getpass(3)`, never from `argv` — a command-line
argument would land in `ps` output and in shell history.

## Why it lives here

It was previously carried in a personal repo that had **no upstream remote**, and
the binary in use had been built from source that was never committed. That is a
single-disk-failure away from gone, and the tool guards credentials. Consolidated
into 0x58 on 2026-08-09 so it is versioned alongside the rest of the machine setup.

Related: [`../secretive-key-rotation.md`](../secretive-key-rotation.md) covers the
Secure Enclave SSH keys — a different mechanism for a different job (SSH auth and
git signing, where the private key must never be extractable). keymaster is for
arbitrary secrets a script needs the *plaintext* of.

## Build and install

`restore.sh` compiles and installs this automatically on macOS. To do it by hand:

```bash
swiftc -O macos/keymaster/keymaster.swift -o ~/.local/bin/keymaster
```

Requires the Xcode Command Line Tools (`xcode-select --install`). The compiled
binary is gitignored — build it, don't commit it.

## Lookup behaviour

`get` tries an exact match on both `kSecAttrService` and `kSecAttrAccount` (what
`set` writes), then falls back to a service-only query. The fallback exists because
items stored by other tools commonly set only the service attribute, and without it
`get` reports "not found" for a secret that is plainly visible in Keychain Access.

## Caveats

- Touch ID gating comes from `LAContext` with
  `touchIDAuthenticationAllowableReuseDuration = 0`, so every `get` re-prompts
  rather than reusing a recent unlock.
- Items are stored as generic passwords in the login keychain. A keychain reset or
  a wiped biometric enrolment loses them — treat it as a convenience cache for
  secrets that can be re-issued, not as the only copy of anything.
