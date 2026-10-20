# External SSD `pourquoimoi`

A 1 TB SanDisk Creator Pro SSD holds the data that grows: the Go build cache and
the two VM disks. It is encrypted APFS, set up on 2026-10-20. That day the
internal disk went from 26 GiB free to 80 GiB free.

## What lives there

| Data | Path on the SSD | How it gets there | Without the SSD |
|---|---|---|---|
| Go build cache | `go-build/` | `bin/gocache-switch`, a LaunchAgent, runs `go env -w GOCACHE` on every mount and unmount | Go uses `~/Library/Caches/go-build`, which `bin/cache-cap` keeps under 20 GiB |
| Podman VM disk | `podman/applehv/podman-machine-default-arm64.raw` | symlink at the same name in `~/.local/share/containers/podman/machine/applehv/` | `podman machine start` should fail on the missing disk (not tested) |
| OrbStack data | `orbstack/data/` | symlink from `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data` | OrbStack refuses to start: `mkdir … data: file exists`. It does not replace the symlink. |
| Codex home | `codex/` | symlink from `~/.codex` | Codex refuses to start: `Error loading configuration` |

Claude Code stays on the internal disk (`~/.claude → ~/src/claude`). Its
transcripts and `memory/` folders are state, not cache: nothing rebuilds them.

## Before you unplug

Run `pourquoimoi-eject`. It stops the podman machine and OrbStack, refuses while
any other process holds a file on the SSD, and then ejects. macOS refuses to
eject while a VM holds its disk, and pulling the cable under a running VM can
break the VM's filesystem.

## Setting up a drive

1. Plug it into a Mac USB-C port, not the desk hub. Through the USB 2.0 hub it
   linked at 480 Mb/s; direct, at 10 Gb/s. Check the link with
   `system_profiler SPUSBHostDataType | grep -A8 'Creator Pro'`.
2. Erase it as APFS, then encrypt it: `diskutil apfs encryptVolume <diskNsM> -user disk`.
   The command asks for the passphrase on a hidden prompt. Disk Utility's format
   menu puts "APFS (Encrypted)" next to "APFS (Case-sensitive)", so confirm with
   `diskutil info <diskNsM> | grep FileVault`.
3. An unmount locks the volume, and a passphrase set with `diskutil` is not in
   the keychain. Mount it once from Disk Utility and tick "Remember this password
   in my keychain".
4. `sudo mdutil -i off /Volumes/pourquoimoi`, so Spotlight does not index caches.

## Measured on 2026-10-20

- `go build ./...` on go-monorepo, warm, RAM page cache purged: 12.6 s internal,
  12.3 s SSD. The SSD costs nothing at 10 Gb/s.
- The Go build cache regrew 30 GiB in 9 days with 7 go-monorepo worktrees.

## Traps found while moving the VMs

- **Sparse files.** `cp` keeps a sparse layout, but it ran CPU-bound at 19 MB/s:
  25.5 GiB took 23 min. `ditto` and `dd conv=sparse bs=1m` write the holes out.
  OrbStack's 24 GiB became 228 GiB, because its data sits in scattered 4 KiB
  blocks. A copier that follows `SEEK_DATA`/`SEEK_HOLE` took 39 s. Verify with
  `openssl dgst -sha256` on both files; `cmp` reads the full length at 240 MB/s.
- **Podman containers started with `--rm`** are deleted when the VM stops.
- **Codex keys its keychain login to the real path of its home.** The keychain
  item `Codex Auth` has the account `cli|<hash>`. Behind the symlink, Codex said
  `Not logged in` until `codex login` ran again.
- **A relative symlink inside `~/.codex` breaks behind the symlink.**
  `skills/web-design-guidelines -> ../../.agents/...` resolved from the SSD. Make
  such links absolute.
- **Any `orb` command starts OrbStack**, `orb config show` included. Stop it first.
