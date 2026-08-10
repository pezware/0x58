#!/bin/bash

# Kubernetes context management
# Supports: EKS, GKE (fleet/connect gateway), Kind (local CLI or a remote node)
#
# Per-window isolation: In kitty, each panel maintains its own active context.
# All panels see all contexts, but `kubectx`/`kube-use` only changes the current panel.

KUBECONFIG_DIR="${HOME}/.kube/configs"

# --- Per-pane / per-window context isolation ---
# KUBECONFIG is a colon-separated merge list. kubectl reads from all files,
# but writes (current-context) go to the FIRST file. By putting a per-pane
# overlay first, each shell instance gets its own active context.
#
# Precedence:
#   1. $TMUX_PANE       → per-tmux-pane isolation (works in any host terminal)
#   2. $KITTY_WINDOW_ID → per-kitty-window isolation when tmux is not in play
# Was 'orbstack' until OrbStack was removed (2026-08-09). A default naming a
# context that no longer exists is worse than useless: every new pane stamps it
# into a fresh overlay, so kubectl fails on a cluster you cannot reach. Defaults
# to the read-only staging context; override per-shell with KUBE_DEFAULT_CONTEXT.
KUBE_DEFAULT_CONTEXT="${KUBE_DEFAULT_CONTEXT:-gke-stg-ro}"
_KUBE_WINDOW_FILE=""
_kube_overlay_id=""
if [[ -n "$TMUX_PANE" ]]; then
  _kube_overlay_id="tmux-${TMUX_PANE#%}"
elif [[ -n "$KITTY_WINDOW_ID" ]]; then
  _kube_overlay_id="kitty-${KITTY_WINDOW_ID}"
fi

if [[ -n "$_kube_overlay_id" ]]; then
  _KUBE_WINDOW_DIR="${KUBECONFIG_DIR}/.window-overlays"
  mkdir -p "$_KUBE_WINDOW_DIR" 2>/dev/null
  _KUBE_WINDOW_FILE="${_KUBE_WINDOW_DIR}/${_kube_overlay_id}.yaml"

  # Fresh overlay on each new shell. Env-var guard prevents re-source from
  # clobbering. File-existence guard prevents the outer shell's init flag
  # from leaking into tmux panes via tmux server env (which would otherwise
  # cause every tmux pane to skip creating its own overlay).
  if [[ -z "$_KUBE_OVERLAY_INIT" ]] || [[ ! -f "$_KUBE_WINDOW_FILE" ]]; then
    export _KUBE_OVERLAY_INIT=1
    command cat > "$_KUBE_WINDOW_FILE" <<YAML
apiVersion: v1
kind: Config
current-context: ${KUBE_DEFAULT_CONTEXT}
contexts: []
clusters: []
users: []
YAML
  fi

  # Clean up stale overlays older than 7 days
  find "$_KUBE_WINDOW_DIR" -name "*.yaml" -mtime +7 -delete 2>/dev/null
fi
unset _kube_overlay_id

# Build KUBECONFIG: window overlay (receives writes) + all config dirs (read-only)
_kube_build_path() {
  local parts=()

  # Window overlay first — kubectl writes current-context here
  if [[ -n "$_KUBE_WINDOW_FILE" ]]; then
    parts+=("$_KUBE_WINDOW_FILE")
  fi

  # All config directories (sorted for stable ordering)
  local dir
  for dir in "$KUBECONFIG_DIR"/*/; do
    [[ "$(basename "$dir")" == ".window-overlays" ]] && continue
    [[ -f "${dir}config" ]] && parts+=("${dir}config")
  done

  local IFS=":"
  echo "${parts[*]}"
}

# Set KUBECONFIG on shell startup
export KUBECONFIG="$(_kube_build_path)"

# --- Core ---

# Refresh KUBECONFIG after adding/removing config directories
kube-refresh() {
  export KUBECONFIG="$(_kube_build_path)"
  echo "KUBECONFIG refreshed. Contexts:"
  kubectl config get-contexts -o name 2>/dev/null
}

# Switch context (per-window in kitty, global otherwise)
kube-use() {
  local context=$1
  if [[ -z "$context" ]]; then
    echo "Usage: kube-use <context>"
    echo ""
    kubectl config get-contexts 2>/dev/null
    return 1
  fi
  kubectl config use-context "$context"
}

# Show current context and config sources
kube-current() {
  echo "Context: $(kubectl config current-context 2>/dev/null || echo '(none)')"
  if [[ -n "$_KUBE_WINDOW_FILE" ]]; then
    if [[ -n "$TMUX_PANE" ]]; then
      echo "Pane:    tmux ${TMUX_PANE} (isolated)"
    elif [[ -n "$KITTY_WINDOW_ID" ]]; then
      echo "Window:  kitty #${KITTY_WINDOW_ID} (isolated)"
    fi
  fi
  echo "Sources:"
  echo "$KUBECONFIG" | tr ':' '\n' | while read -r f; do
    if [[ -f "$f" ]]; then echo "  $f"; else echo "  $f (missing)"; fi
  done
}

# List available contexts
kube-list() {
  kubectl config get-contexts 2>/dev/null
  echo ""
  echo "Config directories:"
  ls -1 "$KUBECONFIG_DIR" | grep -v '^\.'
}

# --- Setup: EKS ---
kube-setup-eks() {
  local env=$1 cluster_name=$2 region=$3
  if [[ -z "$env" || -z "$cluster_name" ]]; then
    echo "Usage: kube-setup-eks <env> <cluster-name> [region]"
    echo "Example: kube-setup-eks dev my-cluster eu-central-2"
    return 1
  fi
  local config_dir="$KUBECONFIG_DIR/eks-$env"
  mkdir -p "$config_dir"
  KUBECONFIG="$config_dir/config" aws eks update-kubeconfig \
    --name "$cluster_name" \
    --region "${region:-eu-central-2}" \
    --alias "eks-$env"
  echo "EKS $env -> $config_dir/config"
  kube-refresh
}

# --- Setup: GKE (fleet / connect gateway) ---
kube-setup-gke() {
  local env=$1 cluster=$2 location=$3 project=$4
  if [[ -z "$env" || -z "$cluster" ]]; then
    echo "Usage: kube-setup-gke <env> <cluster> [location] [project]"
    echo "  location defaults to europe-west4"
    echo "  project  defaults to iden2-ops-<env>"
    echo ""
    echo "Example: kube-setup-gke staging iden2-staging-gke"
    return 1
  fi
  local config_dir="$KUBECONFIG_DIR/gke-$env"
  mkdir -p "$config_dir"
  KUBECONFIG="$config_dir/config" gcloud container fleet memberships get-credentials "$cluster" \
    --location "${location:-europe-west4}" \
    --project "${project:-iden2-ops-${env}}"
  # Rename the long connectgateway_* context to gke-<env>
  local generated_ctx
  generated_ctx=$(KUBECONFIG="$config_dir/config" kubectl config get-contexts -o name 2>/dev/null | head -1)
  if [[ -n "$generated_ctx" && "$generated_ctx" != "gke-$env" ]]; then
    KUBECONFIG="$config_dir/config" kubectl config rename-context "$generated_ctx" "gke-$env"
  fi
  echo "GKE $env -> $config_dir/config (context: gke-$env)"
  kube-refresh
}

# --- Setup: Kind on a REMOTE node (the on-demand k8s box) ---
# The cluster lives on a separate Linode, so `kind get kubeconfig` has to run
# there -- it needs kind and a docker socket, neither of which exist locally.
# `kind get kubeconfig` prints to stdout, so the whole import is one hop.
#
# The kubeconfig it emits already points at the node's TAILNET address, because
# roles/k8s/bootstrap.sh sets apiServerAddress at cluster-creation time. That
# cannot be retrofitted -- the API server bakes its SANs into the serving cert --
# so a cluster built without it is unreachable from here no matter what you edit.
kube-setup-kind-remote() {
  local host=${1:-pezware-k8s} name=${2:-dev}
  local config_dir="$KUBECONFIG_DIR/kind-$name"
  mkdir -p "$config_dir"

  if ! ssh -o ConnectTimeout=15 "$host" "kind get kubeconfig --name '$name'" > "$config_dir/config" 2>/dev/null; then
    echo "Error: could not fetch kubeconfig for '$name' from $host"
    echo "  is the node up?   ts-node k8s status"
    echo "  tailnet ACL must allow tag:devbox -> tag:k8s over ssh and :6443"
    rm -f "$config_dir/config"
    return 1
  fi
  # An empty file here means the ssh hop was refused rather than kind failing --
  # a distinction worth making, because the two look identical downstream.
  if [[ ! -s "$config_dir/config" ]]; then
    echo "Error: empty kubeconfig — the ssh hop to $host probably failed"
    rm -f "$config_dir/config"
    return 1
  fi

  echo "Kind $name @ $host -> $config_dir/config ($(grep -m1 'server:' "$config_dir/config" | tr -d ' '))"
  kube-refresh
}

kube-setup-kind() {
  local name=$1
  if [[ -z "$name" ]]; then
    echo "Usage: kube-setup-kind <cluster-name>"
    if command -v kind &>/dev/null; then
      echo "Available: $(kind get clusters 2>/dev/null | tr '\n' ' ')"
    fi
    return 1
  fi
  local config_dir="$KUBECONFIG_DIR/kind-$name"
  mkdir -p "$config_dir"

  # Requires the kind CLI. The old fallback -- scraping a `kind-*` context out of
  # ~/.kube/config -- existed only for OrbStack-managed kind, which is gone; with
  # no local container runtime there is nothing for it to find. For a cluster on
  # the k8s node, use kube-setup-kind-remote instead.
  if ! command -v kind &>/dev/null; then
    echo "Error: kind CLI not found. For a remote cluster: kube-setup-kind-remote"
    return 1
  fi
  kind export kubeconfig --name "$name" --kubeconfig "$config_dir/config"
  echo "Kind $name -> $config_dir/config"
  kube-refresh
}

# Clean this kitty window's overlay back to the empty stub (preserves
# current-context). Use after a `kind delete + kind create` cycle, or
# anytime kubectl behaves weirdly because of stale cluster/context/user
# entries that `kind export kubeconfig` (without --kubeconfig flag,
# e.g. from `task switch:kind` or `task kind:up`) dumped into this
# window's overlay file.
kube-clean-overlay() {
  if [[ -z "$_KUBE_WINDOW_FILE" ]]; then
    echo "Not in an isolated context (no tmux pane / kitty window) — nothing to clean."
    return 0
  fi
  local current
  current=$(kubectl config current-context 2>/dev/null || echo "$KUBE_DEFAULT_CONTEXT")
  command cat > "$_KUBE_WINDOW_FILE" <<YAML
apiVersion: v1
kind: Config
current-context: ${current}
contexts: []
clusters: []
users: []
YAML
  echo "Cleaned $_KUBE_WINDOW_FILE (current-context=${current})."
}

# Refresh kind config after a cluster recreate (new CA + maybe new port).
# Combines: re-export to dedicated file + clean window overlay.
# Run after `task switch:kind` or `task kind:up` if you hit
# "TLS verify failed" or "connection refused" from kubectl.
kube-refresh-kind() {
  local name=${1:-iden2-dev}
  if ! kind get clusters 2>/dev/null | grep -q "^${name}$"; then
    echo "Kind cluster '${name}' not found. Available: $(kind get clusters 2>/dev/null | tr '\n' ' ')"
    return 1
  fi
  kube-setup-kind "$name"   # rewrites $config_dir/config with fresh CA/port
  kube-clean-overlay        # removes stale cluster/context/user from overlay
  kubectl config use-context "kind-${name}" >/dev/null
  echo "Kind '${name}' refreshed and active. kubectl now points to kind-${name}."
}

# --- Aliases ---
alias k='kubectl'
alias kc='kube-current'
alias kl='kube-list'

# --- Tab completion ---
_kube_use_completions() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "$(kubectl config get-contexts -o name 2>/dev/null)" -- "$cur"))
}
complete -F _kube_use_completions kube-use

_kube_setup_kind_completions() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  if command -v kind &>/dev/null; then
    COMPREPLY=($(compgen -W "$(kind get clusters 2>/dev/null)" -- "$cur"))
  fi
}
complete -F _kube_setup_kind_completions kube-setup-kind
complete -F _kube_setup_kind_completions kube-refresh-kind

# --- EKS cluster-switcher wrapper ---
# Note: this replaces KUBECONFIG entirely (cluster-switcher's behavior).
# After using eks-switch, run kube-refresh to restore merged config.
eks-switch() {
  local env=$1
  if [[ -z "$env" ]]; then
    echo "Usage: eks-switch <dev|stg|prd>"
    return 1
  fi
  local output
  output=$(cluster-switcher "$env" 2>&1)
  local exit_code=$?
  echo "$output"
  if [[ $exit_code -eq 0 ]]; then
    local aws_profile kubeconfig
    aws_profile=$(echo "$output" | grep "AWS_PROFILE environment variable set to:" | awk '{print $NF}')
    kubeconfig=$(echo "$output" | grep "KUBECONFIG environment variable set to:" | awk '{print $NF}')
    [[ -n "$aws_profile" ]] && export AWS_PROFILE="$aws_profile"
    [[ -n "$kubeconfig" ]] && export KUBECONFIG="$kubeconfig"
  fi
  return $exit_code
}
