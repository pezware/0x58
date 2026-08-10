# Login Items & BackgroundTaskManagement (BTM)

How macOS registers things to run at login, and how to inspect that registration
when it goes missing. Written originally for the external-drive auto-mount (now
retired — see [History](#history-external-drive-auto-mount-retired-2026-08-09)),
but the mechanics apply to any Login Item.

## Where the registration actually lives

"Open at Login" writes a record into the macOS **BTM database** — **not** a
`~/Library/LaunchAgents/*.plist`. Nothing appears on disk where you would expect
it, which makes a missing Login Item confusing to debug. Inspect it with:

```bash
sfltool dumpbtm | grep -A 6 "<name-fragment>"
# → UUID: 0CF3C882-7F84-4329-BF8C-957E93D6493E
#   Type: user item (0x1)
#   Disposition: [enabled, allowed, visible, not notified]
#   Identifier: file:///Users/arbeitandy/bin/some-script.sh
```

## Registering (and re-registering after the record is lost)

BTM records are lost after Migration Assistant transfers, OS reinstalls, or an
accidental System Settings reset. The script itself is still on disk — only the
launch registration is gone.

1. **System Settings → General → Login Items & Extensions**
2. Under **Open at Login**, click **`+`**
3. Navigate to the script, select it
4. macOS shows a "Background Items Added" notification — that is the BTM acknowledgement
5. Verify with the `sfltool dumpbtm` command above

A shell script appears in that pane as `Kind = "Terminal scripts"`.

Removal is scriptable, unlike adding:

```bash
osascript -e 'tell application "System Events" to delete login item "some-script.sh"'
```

## Disabling temporarily

Toggle it off in the same Settings pane. BTM marks the record
`Disposition: [allowed, visible]` without `enabled` — the record stays, it just
does not run.

## Limitation worth knowing: login-only

Login Items fire **at user login and nothing else**. Anything that must react to
hardware appearing or disappearing mid-session needs a LaunchAgent instead, with
`RunAtLoad: true` (equivalent to the Login Item) plus `WatchPaths` (re-fires on
change). That is roughly 15 lines of plist and a `launchctl load`.

## History: external-drive auto-mount (retired 2026-08-09)

This machine used to keep almost everything on a 1 TB USB drive (`AchtungAndy`,
ExFAT) hosting two sparse images, mounted at login by
`~/bin/external-drives-mount.sh` registered as a Login Item:

| Sparse image | Mounted at | Held |
|---|---|---|
| `OrbStack.dmg.sparseimage` | `/Volumes/OrbStackData` | OrbStack VM/container data |
| `Projects.dmg.sparseimage` | `~/src` via `/etc/fstab` | all project source trees |

Retired because three problems compounded:

1. **It could not be encrypted.** ExFAT has no native macOS encryption, and both
   APFS volumes inside the sparse images reported `FileVault: No`. Every source
   tree — and `~/.claude`, a symlink to `~/src/claude` holding full conversation
   history — sat unencrypted on a removable disk. FileVault on the internal disk
   did nothing for any of it.
2. **Sparse images never shrink.** The OrbStack image occupied 272 GB on the host
   filesystem for a 114 GB volume: ~150 GB was blocks freed inside the image and
   never returned.
3. **The stack was fragile.** ExFAT → sparse image → VM disk meant a brief USB
   stall could wedge the guest kernel on block I/O.

Replaced by: dev work moved to the devbox, OrbStack removed entirely, and the
~700 MB of source actually needed locally moved onto the internal FileVault
volume. `/etc/fstab` and the Login Item were removed with it.

Two lessons worth carrying forward:

- **`df <path>` is the only thing that reveals a directory symlinked onto another
  volume.** A `du` sweep of `$HOME` silently skipped `~/.claude`, so the most
  sensitive directory on the machine was invisible to every space audit.
- **Unmounting reveals files that were hidden underneath the mountpoint.** `~/src`
  was not empty on the internal disk; stale directories had been masked by the
  mount for a year. Check the mountpoint is empty before moving anything into it,
  or `mv` will nest the source inside a directory you did not know was there.
