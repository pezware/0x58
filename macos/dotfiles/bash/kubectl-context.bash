#!/bin/bash

# Kubernetes context management
# Supports: EKS, GKE (fleet/connect gateway), Kind (OrbStack), OrbStack native
#
# Per-window isolation: In kitty, each panel maintains its own active context.
# All panels see all contexts, but `kubectx`/`kube-use` only changes the current panel.

KUBECONFIG_DIR="${HOME}/.kube/configs"

# --- Per-window context isolation (kitty terminal) ---
# KUBECONFIG is a colon-separated merge list. kubectl reads from all files,
# but writes (current-context) go to the FIRST file. By putting a per-window
# overlay first, each kitty panel gets its own active context.
KUBE_DEFAULT_CONTEXT="${KUBE_DEFAULT_CONTEXT:-orbstack}"
_KUBE_WINDOW_FILE=""
if [[ -n "$KITTY_WINDOW_ID" ]]; then
  _KUBE_WINDOW_DIR="${KUBECONFIG_DIR}/.window-overlays"
  mkdir -p "$_KUBE_WINDOW_DIR" 2>/dev/null
  _KUBE_WINDOW_FILE="${_KUBE_WINDOW_DIR}/${KITTY_WINDOW_ID}.yaml"

  # Fresh overlay on each new shell (guard against re-source with env var)
  if [[ -z "$_KUBE_OVERLAY_INIT" ]]; then
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
    echo "Window:  kitty #${KITTY_WINDOW_ID} (isolated)"
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

# --- Setup: Kind (OrbStack-managed or standalone) ---
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

  if command -v kind &>/dev/null; then
    # Standalone kind CLI
    kind export kubeconfig --name "$name" --kubeconfig "$config_dir/config"
  else
    # OrbStack-managed kind: extract from default kubeconfig
    KUBECONFIG="$HOME/.kube/config" kubectl config view \
      --minify --flatten --context="kind-$name" > "$config_dir/config" 2>/dev/null
    if [[ ! -s "$config_dir/config" ]]; then
      echo "Error: context 'kind-$name' not found in ~/.kube/config"
      rm -f "$config_dir/config"
      return 1
    fi
  fi
  echo "Kind $name -> $config_dir/config"
  kube-refresh
}

# --- Setup: OrbStack native Kubernetes ---
kube-setup-orbstack() {
  local config_dir="$KUBECONFIG_DIR/orbstack"
  mkdir -p "$config_dir"
  KUBECONFIG="$HOME/.kube/config" kubectl config view \
    --minify --flatten --context=orbstack > "$config_dir/config" 2>/dev/null
  if [[ ! -s "$config_dir/config" ]]; then
    echo "Error: orbstack context not found. Is OrbStack running?"
    rm -f "$config_dir/config"
    return 1
  fi
  echo "OrbStack -> $config_dir/config"
  kube-refresh
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
