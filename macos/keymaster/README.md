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

The fallback uses `kSecMatchLimitOne`, so if several items share a service and none
has `account == service`, you get whichever one the Keychain returns first. Store
through `keymaster set` and that case does not arise; reach for `security(1)` if
you need to disambiguate by account.

## What the Touch ID prompt does and does not protect

**The prompt gates this CLI, not the Keychain item.** Items are written with
`kSecAttrAccessibleWhenUnlocked` and no `SecAccessControl`, and the `LAContext`
`get` builds is not passed to `SecItemCopyMatching`. So the biometric check is a
control-flow gate inside keymaster: it stops a casual `keymaster get`, but the
underlying secret is readable by anything running as you, with no prompt at all:

```bash
security find-generic-password -w -s <key>   # returns the secret, no Touch ID
```

That is materially weaker than the Secure Enclave guarantee behind
[Secretive](../secretive-key-rotation.md), where the private key cannot be
extracted at all. Treat keymaster as "keeps secrets out of dotfiles, shell history
and `ps` output", not as "an attacker with code execution as me cannot read this".

Closing the gap means attaching `SecAccessControl` with
`.biometryCurrentSet`/`.userPresence` at `set` time and passing
`kSecUseAuthenticationContext` at `get` time. It is a breaking change — items
already stored are not retroactively protected and would need rewriting — so it is
deliberately not bundled with the 2026-08-09 consolidation.

## Other caveats

- `touchIDAuthenticationAllowableReuseDuration = 0`, so every `get` re-prompts
  rather than reusing a recent unlock.
- Items are generic passwords in the login keychain. A keychain reset or a wiped
  biometric enrolment loses them — treat it as a convenience cache for secrets
  that can be re-issued, not as the only copy of anything.
