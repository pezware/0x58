# Linux setup — old ThinkPad as a headless SSH server

Target: a 64-bit Intel ThinkPad, 2–4 GB RAM, no graphical UI, reachable over SSH.

## Why Debian netinst, not Ubuntu

The complaint that started this was Ubuntu's package management — snapd, the Pro
nags, Firefox-as-a-snap. Debian's `apt` is the same tool with none of that layered
on top.

The second reason is more practical: **the Ubuntu USB stopped booting on this
laptop even though an older Ubuntu ran fine.** That is almost always the *live
session*, not the install. Modern Ubuntu desktop images boot a full GNOME live
environment before the installer appears, which now wants ~4 GB of RAM and a
GPU stack this vintage of Intel graphics no longer satisfies. Older releases used
a lighter live session, which is why the old USB worked.

Debian's **netinst** image sidesteps this entirely — it boots a text-mode
(ncurses) installer that runs comfortably in a few hundred MB and never
initialises a desktop. If the hardware itself were failing you would see it here
too, which makes this a useful diagnostic as well as an install.

> If netinst *also* fails to boot, the problem is below the OS: try another USB
> stick, check the BIOS boot order and any Secure Boot setting, and consider that
> a decade-old spinning disk may simply be dying.

## Install

1. Download the **amd64 netinst** image from <https://www.debian.org/distrib/>
   (~700 MB). Non-free firmware has shipped on the official image since Debian
   12, so Intel wifi/ethernet is detected during install — the old "Debian can't
   see my wifi" trap is gone.

2. Write it to the USB stick:
   ```bash
   # macOS — diskutil list first to confirm the disk number, this is destructive
   diskutil unmountDisk /dev/diskN
   sudo dd if=debian-13.x.0-amd64-netinst.iso of=/dev/rdiskN bs=4m status=progress
   ```

3. Boot it and take the defaults **except at tasksel** — this is checklist item 3,
   and it is the one step that cannot be fixed by a script afterwards. Uncheck
   everything, then select only:

   - [x] **SSH server**
   - [x] **standard system utilities**
   - [ ] ~~Debian desktop environment~~ ← the whole point; leave unchecked
   - [ ] ~~GNOME / KDE / Xfce~~

   Result: a system that idles around 150 MB, so 2 GB of RAM is genuinely
   comfortable. Verify afterwards with `systemctl get-default` — you want
   `multi-user.target`, not `graphical.target`.

4. Wired ethernet is strongly preferred for a server. Use wifi only if you must.

## Partitioning

Use **Guided – use entire disk and set up LVM**. Not the *encrypted* variant: on
a headless box LUKS blocks every boot at the console waiting for a passphrase,
and the machine stays unreachable until someone physically types it.

When the installer asks **"Amount of volume group to use for guided
partitioning"**, do not accept the maximum — that discards the entire point of
LVM. On a 128 GB disk, entering ~80 GB gives:

| Volume | Type | Size |
|---|---|---|
| ESP | plain | 512 MB (UEFI only) |
| `/boot` | plain ext4 | 1 GB |
| `swap` LV | swap | 4 GB |
| `root` LV | ext4 | 30 GB — `/home` lives here, and mise puts ~5-10 GB of toolchains in it |
| `var` LV | ext4 | 45 GB — container images and logs land here |
| *unallocated* | — | ~47 GB held in reserve |

The reserve is the feature: `lvextend -L +20G /dev/vg/var && resize2fs /dev/vg/var`
grows `/var` online when image churn outpaces the guess. ext4 rather than XFS
because XFS cannot shrink, and one-way resizing is a poor trade when you are
estimating sizes up front.

A separate `/var` also contains the classic failure: a runaway container log
filling the disk takes out the whole system, including your ability to SSH in
and clean it up.

> Note for k8s: kubelet refuses to start with swap enabled (`--fail-swap-on`
> defaults true). Either `swapoff -a` plus a commented fstab line, or set
> `--fail-swap-on=false` deliberately. The 4 GB LV costs little and keeps both
> options open — `apt` and `mise install` can OOM without it on a 2-4 GB box.

## Bootstrap

On a bare machine, one command:

```bash
bash -c "$(curl -fsSL https://m.pezware.com/linux-start.sh)"
```

Prefer that form over `curl ... | bash` — piping puts the script on stdin, so a
`sudo` re-prompt or an apt conffile question would consume the script's own bytes
instead of your keystrokes. See [`../cloudflare/`](../cloudflare/) for how that
URL is served (it is a Worker; a CNAME cannot do it).

Straight from GitHub, no Cloudflare involved:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/pezware/0x58/main/linux/start.sh)"
```

Or by hand, if you would rather read before you run:

```bash
sudo apt install -y git ca-certificates          # just enough to clone
git clone https://github.com/pezware/0x58 ~/src/public/0x58
cd ~/src/public/0x58
HEADLESS=1 ./macos/restore.sh                    # packages + dotfiles + lid/battery
```

[`start.sh`](start.sh) installs git, clones or fast-forwards the repo, and hands
off to `restore.sh`, which detects Linux and installs from
[`packages.txt`](packages.txt). `HEADLESS=1` additionally runs
[`setup-server.sh`](setup-server.sh) — leave it off for VMs and containers, which
have neither a lid nor a battery:

```bash
HEADLESS=1 bash -c "$(curl -fsSL https://m.pezware.com/linux-start.sh)"
```

Then follow the numbered manual steps the script prints at the end (auth, SSH
key, Tailscale, `mise install`).

## What owns what

| Layer | Tool | Source of truth |
|---|---|---|
| Base system | `apt` | [`linux/packages.txt`](packages.txt) |
| Dev tools + runtimes | `mise` | [`dotfiles/mise/config.toml`](../dotfiles/mise/config.toml) — already cross-platform |
| Dotfiles | `restore.sh` | [`macos/dotfiles/`](../macos/dotfiles/) |

**Homebrew is deliberately not used here.** It would be 1–3 GB of disk, and any
formula lacking an `x86_64_linux` bottle compiles from source on a CPU where that
takes hours. `mise` already covers ~50 of the tools in the Brewfile, portably —
so on Linux the Brewfile's job shrinks to a handful of binaries, none of which
justify a second package manager.

## Laptop-as-server gotchas

Handled by `setup-server.sh`:

1. **Lid close suspends the machine**, killing every SSH session. Fixed with a
   drop-in at `/etc/systemd/logind.conf.d/10-0x58-headless.conf` (a drop-in, not
   an edit to `logind.conf`, so it survives package upgrades).
2. **Permanent AC swells the battery.** ThinkPads expose a charge ceiling through
   the in-kernel `thinkpad_acpi` driver — no `tlp` needed. The sysfs value resets
   each boot, so a systemd oneshot reapplies it. Default 80%; override with
   `BATT_STOP_THRESHOLD=60 bash linux/setup-server.sh`.

Not handled, worth knowing:

- **Console blanking** on a headless box is harmless, but if you ever attach a
  screen to debug, `setterm --blank 0` saves confusion.
- **`TERM`** needs nothing special: `config-kitty/kitty.conf` already sets
  `term xterm-256color` precisely so remote hosts without kitty's terminfo work.
- **Disk** — if this ThinkPad still has a spinning HDD, a cheap SATA SSD is by
  far the biggest single improvement available to it.
