# External Drives & Auto-Mount

Most working files live on an external USB drive (`AchtungAndy`) which hosts two
sparseimages that get mounted at login:

| Sparseimage | Mount point | Used for |
|---|---|---|
| `OrbStack.dmg.sparseimage` | `/Volumes/OrbStackData` → symlinked into `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data` | OrbStack VM/container data (large) |
| `Projects.dmg.sparseimage` | `/Volumes/ProjectsData` → mounted to `~/src` via `/etc/fstab` | All project source trees |

The auto-mount is driven by [`external-drives-mount.sh`](external-drives-mount.sh),
which on a fresh install lives at `~/bin/external-drives-mount.sh`.

## What the script does (in order)

1. Wait up to 60s for `/Volumes/AchtungAndy` (USB enumeration can lag the Login Item)
2. Attach `OrbStack.dmg.sparseimage` → `/Volumes/OrbStackData`
3. Attach `Projects.dmg.sparseimage` → `/Volumes/ProjectsData` → mounted to `~/src` via `/etc/fstab`
4. Restore the OrbStack symlink (`~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data` → `/Volumes/OrbStackData/orbstack-data`)
5. Launch `OrbStack.app` if not already running

Logs append to `~/Library/Logs/external-drives-mount.log` (one `===` banner per run).

## Auto-run setup (Login Items)

The script is registered to auto-run via **System Settings → General →
Login Items & Extensions → Open at Login**. The .sh file appears there as
`Kind = "Terminal scripts"`.

### Under the hood: BackgroundTaskManagement (BTM)

The setting writes a record into the macOS BTM database — **not** a
`~/Library/LaunchAgents/*.plist`. Verify with:

```bash
sfltool dumpbtm | grep -A 6 "external-drives"
# → UUID: 0CF3C882-7F84-4329-BF8C-957E93D6493E
#   Type: user item (0x1)
#   Disposition: [enabled, allowed, visible, not notified]
#   Identifier: file:///Users/arbeitandy/bin/external-drives-mount.sh
```

### Re-registering after the BTM record is lost

This happens after Migration Assistant transfers, OS reinstalls, or an
accidental System Settings reset. The script file is still on disk — only
the launch registration is missing.

1. **System Settings → General → Login Items & Extensions**
2. Under **Open at Login**, click **`+`**
3. Navigate to `~/bin/external-drives-mount.sh`, select it
4. macOS shows a "Background Items Added" notification — that's the BTM acknowledgement
5. Verify with the `sfltool dumpbtm | grep` command above

### Disabling temporarily

Toggle off in the same Settings pane. BTM marks it
`Disposition: [allowed, visible]` without `enabled` — record stays, just
not running.

## Known limitation: doesn't survive mid-session disconnects

Login Items only fire **at user login**. If `AchtungAndy` disconnects
mid-session (USB jiggle, sleep/wake quirk) and reattaches later, the
script does **not** re-run — OrbStack will silently lose its data volume
until next login.

### When to migrate to a LaunchAgent

If mid-session disconnects become a real problem, replace the Login Item
with a `~/Library/LaunchAgents/com.local.external-drives-mount.plist`
LaunchAgent that has both:

- `RunAtLoad: true` (replaces today's Login Item behavior)
- `WatchPaths: ["/Volumes"]` (re-fires on USB attach/detach)

It would be a strict superset of today's behavior — about 15 lines of
plist + `launchctl load`. Not done yet because the limitation hasn't
caused real pain.

## Recovery on a fresh machine

If you've just restored a Mac from this repo:

1. Plug in the AchtungAndy external drive
2. Run `./macos/restore.sh` (which copies `external-drives-mount.sh` to `~/bin/`)
3. Register it as a Login Item per the [Re-registering](#re-registering-after-the-btm-record-is-lost) section above
4. Reboot once to confirm: after login, `/Volumes/OrbStackData` and `/Volumes/ProjectsData` should appear within ~60s, and `~/src` should be populated

The sparseimages themselves are on the USB drive (not in this repo) — they
contain the actual data and would be huge anyway. Make sure the USB drive
has its own backup (Time Machine to a separate disk, or another USB).
