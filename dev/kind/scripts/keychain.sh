# Keychain helpers for agent-lab. Source this from Taskfile cmds.
#
# Lookup order for each key:
#   1. macOS Keychain  (security find-generic-password -s <name> -a $USER -w)
#   2. Shell env var    (uppercase, dashes -> underscores: anthropic-api-key -> ANTHROPIC_API_KEY)
#   3. Fail loud (kc_get) or return empty (kc_get_optional)
#
# Why this order:
#   Keychain is encrypted at rest and survives reboots, so it's the canonical
#   store. Env var is a convenience escape hatch (e.g. CI, ephemeral testing,
#   1Password CLI shell integration) without bloating the keychain.

# Required: prints value to stdout, returns 1 with setup instructions on miss.
kc_get() {
  local name="$1"
  local env_name
  env_name=$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')

  local val
  val=$(security find-generic-password -s "$name" -a "$USER" -w 2>/dev/null) || true
  if [ -n "$val" ]; then
    printf '%s' "$val"
    return 0
  fi

  val="${!env_name:-}"
  if [ -n "$val" ]; then
    printf '%s' "$val"
    return 0
  fi

  cat >&2 <<EOF
ERROR: secret '$name' not found.
  Tried Keychain (service='$name', account='$USER') and env \$$env_name.

Add to Keychain (recommended):
  security add-generic-password -s '$name' -a '$USER' -U -w
  # -U updates if exists; -w prompts for the value (no shell history)

Or export for this session:
  export $env_name='...'
EOF
  return 1
}

# Optional: prints value if found, prints nothing (and returns 0) if missing.
kc_get_optional() {
  local name="$1"
  local env_name
  env_name=$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')

  local val
  val=$(security find-generic-password -s "$name" -a "$USER" -w 2>/dev/null) || true
  if [ -n "$val" ]; then
    printf '%s' "$val"
    return 0
  fi
  printf '%s' "${!env_name:-}"
}
