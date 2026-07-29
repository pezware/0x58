#!/usr/bin/env bash
#
# 0x58 — turn a laptop into a headless SSH server.
#
# Two things break a laptop-as-server, and neither is a package you can install:
#   1. Closing the lid suspends the machine, killing every SSH session.
#   2. Sitting on AC at 100% for months swells the battery.
#
# Both are handled here. Idempotent — safe to re-run.
# Called by macos/restore.sh (Phase 4c) or directly:  sudo-less, prompts as needed.
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "setup-server.sh: Linux only (got $(uname -s))" >&2
    exit 1
fi

# Charge ceiling. 80 is the usual longevity/capacity compromise; 60 is kinder
# still if the box never leaves the desk and you don't need runtime on battery.
BATT_STOP_THRESHOLD="${BATT_STOP_THRESHOLD:-80}"

# --- 1. Lid close must not suspend the machine ---
# Written as a drop-in under logind.conf.d/ rather than editing logind.conf
# directly, so the setting survives package upgrades that rewrite the main file.
# (Same reasoning as /etc/pam.d/sudo_local on the macOS side of this repo.)
setup_lid_switch() {
    local dropin=/etc/systemd/logind.conf.d/10-0x58-headless.conf

    if [[ -f "$dropin" ]]; then
        echo "==> Lid switch: already configured ($dropin)"
        return
    fi

    echo "==> Lid switch: ignoring lid close (sudo prompt incoming)"
    sudo mkdir -p /etc/systemd/logind.conf.d
    sudo tee "$dropin" >/dev/null <<'CONF'
# 0x58: this laptop is a headless server and lives with the lid shut.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
CONF

    # Deliberately NOT restarting systemd-logind here: this script is usually run
    # over SSH, and restarting logind can tear down active sessions. Applying at
    # reboot is the safe default.
    echo "    written — takes effect on reboot, or apply now with:"
    echo "      sudo systemctl restart systemd-logind   # may drop your SSH session"
}

# --- 2. Battery charge ceiling ---
# ThinkPads expose charge thresholds through the in-kernel thinkpad_acpi driver,
# so no extra package (tlp, acpi-call, ...) is required. The sysfs value resets
# on every boot, hence the systemd oneshot to reapply it.
setup_battery_threshold() {
    local unit=/etc/systemd/system/0x58-battery-threshold.service
    local sysfs="" candidate
    # Glob rather than parsing `ls`, so an unmatched pattern is handled explicitly.
    for candidate in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
        [[ -e "$candidate" ]] && { sysfs="$candidate"; break; }
    done

    if [[ -z "$sysfs" ]]; then
        echo "==> Battery threshold: no charge_control_end_threshold in sysfs — skipping"
        echo "    (not a ThinkPad, or thinkpad_acpi not loaded — check: lsmod | grep thinkpad)"
        return
    fi

    echo "==> Battery threshold: capping charge at ${BATT_STOP_THRESHOLD}% ($sysfs)"
    echo "$BATT_STOP_THRESHOLD" | sudo tee "$sysfs" >/dev/null

    # Always render, then replace only on difference. Returning early when the
    # unit merely exists would let a re-run with a new BATT_STOP_THRESHOLD write
    # the live sysfs value while leaving the OLD value baked into ExecStart —
    # so the change would silently revert at the next boot.
    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<UNIT
[Unit]
Description=0x58 — cap battery charge for laptop-as-server
ConditionPathExists=$sysfs
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo $BATT_STOP_THRESHOLD > $sysfs'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

    if sudo cmp -s "$tmp" "$unit" 2>/dev/null; then
        echo "    boot-time unit already current ($unit)"
        rm -f "$tmp"
        return
    fi

    sudo install -m 644 "$tmp" "$unit"
    rm -f "$tmp"
    sudo systemctl daemon-reload
    sudo systemctl enable 0x58-battery-threshold.service >/dev/null
    echo "    enabled 0x58-battery-threshold.service (reapplies ${BATT_STOP_THRESHOLD}% on boot)"
}

# --- 3. Report ---
# Item 3 of the checklist (minimal tasksel selection) is an install-time choice
# and cannot be scripted after the fact — see linux/setup-guide.md.
print_status() {
    echo ""
    echo "==> Headless server status"
    echo "    lid switch : $(grep -hs HandleLidSwitch= /etc/systemd/logind.conf.d/*.conf | head -1 || echo 'default (suspends!)')"
    if [[ -r /sys/class/power_supply/BAT0/charge_control_end_threshold ]]; then
        echo "    batt cap   : $(cat /sys/class/power_supply/BAT0/charge_control_end_threshold)%"
    fi
    echo "    sshd       : $(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo inactive)"
    echo ""
    echo "    Verify a desktop stack did NOT get installed:"
    echo "      systemctl get-default        # want: multi-user.target, not graphical.target"
}

setup_lid_switch
setup_battery_threshold
print_status
