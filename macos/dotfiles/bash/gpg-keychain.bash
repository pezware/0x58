# GPG cold-storage in macOS Keychain (no on-disk backup)
#
# gpg_backup_to_keychain stores ~/.gnupg/ as a base64-encoded gzipped tarball
# in the login keychain (service: gpg-archive-b64). Decoded SHA-256 is embedded
# in the item's kind ('-j') field so integrity is self-describing inside the
# keychain.
#
# A separate cold-storage entry 'keybase-paper-key-b64' is preserved from a
# one-time migration; this script does not regenerate it. To retrieve:
#   security find-generic-password -s keybase-paper-key-b64 -a "$USER" -w \
#     | base64 -d | gpg -d

_gpg_kc_account="${USER:-arbeitandy}"
_gpg_kc_archive="gpg-archive-b64"
_gpg_kc_paper="keybase-paper-key-b64"

gpg_backup_to_keychain() {
  command -v gpg >/dev/null || { echo "gpg not in PATH" >&2; return 1; }
  local tmp; tmp=$(mktemp -d) || return 1
  trap "rm -rf '$tmp'" RETURN

  tar --exclude='S.*' --exclude='*.lock' --exclude='.DS_Store' \
      --exclude='random_seed' --exclude='reader_0.status' \
      -czf "$tmp/archive.tar.gz" -C "$HOME" .gnupg || return 1

  local archive_sha; archive_sha=$(shasum -a 256 "$tmp/archive.tar.gz" | awk '{print $1}')
  base64 < "$tmp/archive.tar.gz" > "$tmp/archive.b64"

  security add-generic-password \
    -s "$_gpg_kc_archive" -a "$_gpg_kc_account" \
    -l "GnuPG cold-storage archive (base64 tar.gz of ~/.gnupg)" \
    -j "decoded sha256 = $archive_sha" \
    -w "$(cat "$tmp/archive.b64")" -U || return 1
  echo "stored $_gpg_kc_archive (sha256: $archive_sha)"
}

gpg_verify_keychain_backup() {
  local item="${1:-$_gpg_kc_archive}"
  local stored_sha actual_sha
  stored_sha=$(security find-generic-password -s "$item" -a "$_gpg_kc_account" 2>/dev/null \
               | awk -F'"' '/icmt|^[[:space:]]*"icmt"|0x00000007 <blob>/ {next} /icmt|kind|"type"/ {next} 1' \
               | grep -oE 'sha256 = [0-9a-f]{64}' | awk '{print $3}')
  if [ -z "$stored_sha" ]; then
    stored_sha=$(security find-generic-password -s "$item" -a "$_gpg_kc_account" 2>&1 \
                 | grep -oE '[0-9a-f]{64}' | head -1)
  fi
  actual_sha=$(security find-generic-password -s "$item" -a "$_gpg_kc_account" -w 2>/dev/null \
               | base64 -d | shasum -a 256 | awk '{print $1}')
  echo "item:    $item"
  echo "stored:  ${stored_sha:-<none>}"
  echo "actual:  $actual_sha"
  [ -n "$stored_sha" ] && [ "$stored_sha" = "$actual_sha" ] && echo "OK" || { echo "MISMATCH" >&2; return 1; }
}

gpg_restore_from_keychain() {
  if [ -d "$HOME/.gnupg" ]; then
    local ts ans
    ts=$(date +%s)
    printf 'Existing ~/.gnupg/ found. Rename to ~/.gnupg.preexisting.%s and continue? [y/N] ' "$ts" >/dev/tty
    read -r ans </dev/tty
    case "$ans" in
      y|Y|yes|YES) mv "$HOME/.gnupg" "$HOME/.gnupg.preexisting.$ts" || return 1 ;;
      *) echo "aborted" >&2; return 1 ;;
    esac
  fi

  security find-generic-password -s "$_gpg_kc_archive" -a "$_gpg_kc_account" -w 2>/dev/null \
    | base64 -d | tar xzf - -C "$HOME" || return 1
  chmod 700 "$HOME/.gnupg"
  echo "restored ~/.gnupg/"
  gpg --list-keys 2>/dev/null | grep -E "^(pub|uid)" | head -10
  echo
  echo "to decrypt the keybase paper key:"
  echo "  security find-generic-password -s $_gpg_kc_paper -a $_gpg_kc_account -w | base64 -d | gpg -d"
}
