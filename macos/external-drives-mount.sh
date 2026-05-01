#!/bin/bash

# Log file for debugging.
# Append (not overwrite) so we keep history across runs — otherwise a manual
# re-run wipes evidence of the previous (possibly failing) login-time run.
LOG_FILE=~/Library/Logs/external-drives-mount.log
{
  echo ""
  echo "================================================================================"
  echo "$(date): Starting external drives mount script"
} >> "$LOG_FILE"

# Function to log messages
log() {
  echo "$(date): $1" >> "$LOG_FILE"
  echo "$1"
}

# Wait for AchtungAndy (the external drive hosting both sparseimages) to be
# mounted before attempting any hdiutil attach. At login time, USB enumeration
# can lag behind the Login Item firing — without this guard the script hits
# hdiutil while /Volumes/AchtungAndy is still missing, gets "no such file",
# bails silently, and never re-runs (Login Items don't retry). 60s is generous
# for the slowest USB enclosures.
wait_for_achtungandy() {
  if [ -d "/Volumes/AchtungAndy" ]; then
    log "AchtungAndy already available"
    return 0
  fi
  log "Waiting for /Volumes/AchtungAndy to be available (USB enumeration)"
  for i in {1..60}; do
    if [ -d "/Volumes/AchtungAndy" ]; then
      log "AchtungAndy available after $i seconds"
      return 0
    fi
    sleep 1
  done
  log "ERROR: /Volumes/AchtungAndy not available after 60 seconds; aborting"
  return 1
}

if ! wait_for_achtungandy; then
  exit 1
fi

# Function to mount disk image if not already mounted
mount_if_needed() {
  local volume_name="$1"
  local image_path="$2"
  local mount_point="/Volumes/$volume_name"

  if [ ! -d "$mount_point" ]; then
    log "Mounting $volume_name disk image"
    hdiutil attach "$image_path"

    # Wait for mount to complete
    for i in {1..30}; do
      if [ -d "$mount_point" ]; then
        log "$volume_name mounted successfully after $i seconds"
        return 0
      fi
      sleep 1
    done

    log "ERROR: Failed to mount $volume_name after 30 seconds"
    return 1
  else
    log "$volume_name already mounted"
    return 0
  fi
}

# Function to create symlink if needed
create_symlink_if_needed() {
  local source="$1"
  local target="$2"
  local description="$3"

  if [ ! -L "$target" ] && [ ! -d "$target" ]; then
    log "Creating symlink for $description: $target -> $source"
    ln -s "$source" "$target"
    if [ $? -eq 0 ]; then
      log "Symlink for $description created successfully"
    else
      log "ERROR: Failed to create symlink for $description"
      return 1
    fi
  elif [ -L "$target" ]; then
    # Verify the symlink points to the right place
    LINK_TARGET=$(readlink "$target")
    if [ "$LINK_TARGET" != "$source" ]; then
      log "WARNING: $description symlink points to $LINK_TARGET instead of $source"
      log "Fixing symlink for $description"
      rm "$target"
      ln -s "$source" "$target"
    else
      log "$description symlink is correct"
    fi
  else
    log "$description target exists as directory, skipping symlink creation"
  fi
}

# Mount OrbStack data
if mount_if_needed "OrbStackData" "/Volumes/AchtungAndy/OrbStack.dmg.sparseimage"; then
  # Ensure OrbStack directory structure
  mkdir -p ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack
  mkdir -p /Volumes/OrbStackData/orbstack-data

  # Handle OrbStack data symlink
  if [ ! -L ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/data ]; then
    if [ -d ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/data ]; then
      log "Backing up existing OrbStack data directory"
      mv ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/data ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/data.original.$(date +%Y%m%d%H%M%S)
    fi
    ln -s /Volumes/OrbStackData/orbstack-data ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/data
    log "OrbStack data symlink created"
  fi
fi

# Mount Projects data
log "Checking Projects sparse image"

# Check if already attached
if ! diskutil list | grep -q "ProjectsData"; then
  log "Attaching Projects sparse image"
  ATTACH_OUTPUT=$(hdiutil attach -nomount "/Volumes/AchtungAndy/Projects.dmg.sparseimage" 2>&1)

  if [ $? -eq 0 ]; then
    # Extract the APFS volume device (looking for the line after Apple_APFS)
    APFS_DEVICE=$(echo "$ATTACH_OUTPUT" | grep -A1 "Apple_APFS" | tail -1 | awk '{print $1}')

    if [ -n "$APFS_DEVICE" ]; then
      log "Found APFS device: $APFS_DEVICE"

      # Find the APFS volume within the container
      APFS_VOLUME=$(diskutil apfs list | grep -B 2 "ProjectsData" | grep "APFS Volume Disk" | awk '{print $5}')

      if [ -n "$APFS_VOLUME" ]; then
        log "Found APFS volume: $APFS_VOLUME"
        # Mount the APFS volume (this will mount to /Volumes/ProjectsData first)
        diskutil mount "$APFS_VOLUME"
      else
        log "ERROR: Could not find ProjectsData APFS volume"
      fi

      # Give it a moment to fully mount
      sleep 1
    else
      log "ERROR: Could not find APFS device in attach output"
    fi
  else
    log "ERROR: Failed to attach Projects sparse image: $ATTACH_OUTPUT"
  fi
else
  log "Projects sparse image already attached"
  # Find the APFS volume and ensure it's mounted
  APFS_VOLUME=$(diskutil apfs list | grep -B 2 "ProjectsData" | grep "APFS Volume Disk" | awk '{print $5}')
  if [ -n "$APFS_VOLUME" ]; then
    log "Found existing APFS volume: $APFS_VOLUME"
    diskutil mount "$APFS_VOLUME" 2>/dev/null
  else
    log "ERROR: Could not find ProjectsData APFS volume"
  fi
fi

# Now trigger the fstab mount to ~/src
if ! mount | grep -q "$HOME/src"; then
  log "Mounting ProjectsData to ~/src via fstab"
  mount "$HOME/src" 2>/dev/null
  if [ $? -eq 0 ]; then
    log "ProjectsData successfully mounted at ~/src"
  else
    log "WARNING: Could not mount to ~/src via fstab"
  fi
else
  log "ProjectsData already mounted at ~/src"
fi

# Start OrbStack if everything is properly mounted
if [ -d "/Volumes/OrbStackData" ] && [ -L ~/Library/Group\ Containers/HUAQ24HBR6.dev.orbstack/data ]; then
  if ! pgrep -f OrbStack > /dev/null; then
    log "Starting OrbStack"
    open -a OrbStack
    log "OrbStack startup initiated"
  else
    log "OrbStack is already running"
  fi
fi

log "External drives mount script completed successfully"
