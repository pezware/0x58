#!/usr/bin/env bash
set -euo pipefail

# Dumps macOS system preferences as `defaults write` commands.
# Review the output and delete stock/unwanted settings.
#
# Usage:
#   ./defaults.sh              # Apply saved defaults
#   ./defaults.sh --dump       # Regenerate defaults from current system
#   ./defaults.sh --dry-run    # Preview commands without applying

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_FILE="$SCRIPT_DIR/defaults-dump.sh"

DOMAINS=(
    com.apple.dock
    com.apple.finder
    NSGlobalDomain
)

dump_defaults() {
    echo "==> Dumping defaults to $DEFAULTS_FILE"
    {
        echo "#!/usr/bin/env bash"
        echo "# macOS defaults — generated $(date -u +%Y-%m-%d)"
        echo "# Review and delete unwanted entries before committing."
        echo "set -euo pipefail"
        echo ""

        for domain in "${DOMAINS[@]}"; do
            echo "# --- $domain ---"
            # Read all keys for this domain
            defaults read "$domain" 2>/dev/null | while IFS= read -r line; do
                # Match lines like '    key = value;'
                if [[ "$line" =~ ^[[:space:]]+\"?([^\"=]+)\"?[[:space:]]*=[[:space:]]*(.+)\;$ ]]; then
                    key="${BASH_REMATCH[1]}"
                    value="${BASH_REMATCH[2]}"
                    # Trim whitespace
                    key="$(echo "$key" | xargs)"
                    value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

                    # Skip complex types (dicts, arrays) — they need special handling
                    [[ "$value" == "(" ]] && continue
                    [[ "$value" == "{" ]] && continue

                    # Determine type flag
                    if [[ "$value" =~ ^[0-9]+$ ]]; then
                        echo "defaults write $domain \"$key\" -int $value"
                    elif [[ "$value" =~ ^[0-9]*\.[0-9]+$ ]]; then
                        echo "defaults write $domain \"$key\" -float $value"
                    elif [[ "$value" == "1" || "$value" == "0" ]]; then
                        echo "defaults write $domain \"$key\" -bool $( [[ "$value" == "1" ]] && echo true || echo false )"
                    elif [[ "$value" =~ ^\"(.*)\"$ ]]; then
                        echo "defaults write $domain \"$key\" -string ${BASH_REMATCH[1]}"
                    else
                        echo "defaults write $domain \"$key\" -string \"$value\""
                    fi
                fi
            done
            echo ""
        done

        echo "# Restart affected services"
        echo "killall Dock 2>/dev/null || true"
        echo "killall Finder 2>/dev/null || true"
    } > "$DEFAULTS_FILE"
    chmod +x "$DEFAULTS_FILE"
    echo "==> Wrote $DEFAULTS_FILE — review and remove stock/unwanted entries"
}

apply_defaults() {
    if [[ ! -f "$DEFAULTS_FILE" ]]; then
        echo "Error: $DEFAULTS_FILE not found. Run with --dump first."
        exit 1
    fi
    echo "==> Applying defaults from $DEFAULTS_FILE"
    bash "$DEFAULTS_FILE"
    echo "==> Done"
}

dry_run() {
    if [[ ! -f "$DEFAULTS_FILE" ]]; then
        echo "Error: $DEFAULTS_FILE not found. Run with --dump first."
        exit 1
    fi
    echo "==> Dry run — commands that would be executed:"
    echo ""
    grep '^defaults write\|^killall' "$DEFAULTS_FILE" || true
}

case "${1:-}" in
    --dump)
        dump_defaults
        ;;
    --dry-run)
        dry_run
        ;;
    "")
        apply_defaults
        ;;
    *)
        echo "Usage: $0 [--dump|--dry-run]"
        exit 1
        ;;
esac
