#!/bin/bash

# Kubernetes context management
# Supports: EKS, GKE (fleet/connect gateway), Kind (local CLI or a remote node)
#
# Per-window isolation: In kitty, each panel maintains its own active context.
# All panels see all contexts, but `kubectx`/`kube-use` only changes the current panel.

KUBECONFIG_DIR="${HOME}/.kube/configs"

# --- Config discovery ---------------------------------------------------------
# The glob IS the registry: adding a cluster means adding a directory, removing
# one means removing it, and there is no list anywhere to keep in sync.
_kube_config_files() {
  local dir
  for dir in "$KUBECONFIG_DIR"/*/; do
    [[ "$(basename "$dir")" == ".window-overlays" ]] && continue
    [[ -f "${dir}config" ]] && printf '%s\n' "${dir}config"
  done
}

# Context names defined by the kubeconfigs named as arguments, one per line.
#
# Parsed with awk rather than `kubectl config get-contexts` because this file is
# sourced from ~/.bashrc well before `mise activate` runs, and kubectl is a
# mise-managed tool on BOTH machines — there is no kubectl on PATH yet. A
# shell-out here returns nothing, which would make every context look undefined:
# the most damaging answer a validator can give, since it is also a plausible one.
#
# Indentation-agnostic on purpose. `kubectl config` writes list items flush left
# ("  name: x"); gcloud writes them indented ("    name: x"). Both styles sit in
# ~/.kube/configs right now, so anchoring on a column parses one file and
# silently misses the other. Track the top-level block instead — a key starting
# at column 0 — and emit every `name:` seen inside `contexts:`.
_kube_contexts_in() {
  [[ $# -eq 0 ]] && return 0
  awk '
    # A top-level key: column 0, and NOT a leading "-". That exclusion is the
    # whole trick — in kubectl style a list item is itself flush left
    # ("- context:"), so treating column 0 as "new top-level block" ends the
    # contexts: block on its own first entry and finds nothing.
    /^[^[:space:]#-]/ { in_ctx = ($0 ~ /^contexts:[[:space:]]*$/); next }
    !in_ctx { next }
    {
      for (i = 1; i < NF; i++)
        if ($i == "name:") { n = $(i + 1); gsub(/"/, "", n); print n; break }
    }
  ' "$@" 2>/dev/null | sort -u
}

# Every context this machine actually holds a definition for.
_kube_all_contexts() {
  local files=() f
  while IFS= read -r f; do files+=("$f"); done < <(_kube_config_files)
  [[ ${#files[@]} -eq 0 ]] && return 0
  _kube_contexts_in "${files[@]}"
}

_kube_context_exists() {
  [[ -n "$1" ]] || return 1
  _kube_all_contexts | command grep -qxF "$1"
}

# --- The default context for a new pane ---------------------------------------
# Empty unless KUBE_DEFAULT_CONTEXT names a context this machine defines.
# Validating it is the entire point.
#
# The old code stamped the value into every fresh overlay unconditionally, which
# made the default a claim nobody checked. It went wrong twice, both live: the
# Mac carried `orbstack` for months after OrbStack was removed, and on
# 2026-08-10 all 23 devbox panes were still pinned to `orbstack` — a context
# that had never existed on Linux in the first place. kubectl stores such a
# dangling pointer without complaint; `current-context` reports the ghost name
# happily and only the first real call fails, with "context was not found for
# specified context". A prompt that reads a stored string is not reporting where
# you are, it is reporting what someone once wrote down.
#
# Assigned with ${VAR-default}, not ${VAR:-default}: an explicit
# KUBE_DEFAULT_CONTEXT="" means "start me with no context", which is a different
# request from "I did not say", and only the unset form should get a default.
#
# Note there is no platform branch here, and there must not be — this file is in
# the SHARED source list in ~/.bashrc, installed verbatim on both machines.
# Validation is what lets one neutral file behave correctly on each: gke-stg-ro
# resolves on the Mac, defines nothing on the devbox, so the devbox starts empty
# and inherits whatever kind cluster it does have.
KUBE_DEFAULT_CONTEXT="${KUBE_DEFAULT_CONTEXT-gke-stg-ro}"

_kube_default_context() {
  _kube_context_exists "$KUBE_DEFAULT_CONTEXT" && printf '%s' "$KUBE_DEFAULT_CONTEXT"
}

# --- Per-pane / per-window context isolation ----------------------------------
# KUBECONFIG is a colon-separated merge list. kubectl reads from all files,
# but writes (current-context) go to the FIRST file. By putting a per-pane
# overlay first, each shell instance gets its own active context.
#
# Precedence:
#   1. $TMUX_PANE       → per-tmux-pane isolation (works in any host terminal)
#   2. $KITTY_WINDOW_ID → per-kitty-window isolation when tmux is not in play
_KUBE_WINDOW_FILE=""
_kube_overlay_id=""
if [[ -n "$TMUX_PANE" ]]; then
  _kube_overlay_id="tmux-${TMUX_PANE#%}"
elif [[ -n "$KITTY_WINDOW_ID" ]]; then
  _kube_overlay_id="kitty-${KITTY_WINDOW_ID}"
fi

# Write the overlay stub, pinning $1 as current-context — or pinning nothing
# when $1 is empty.
#
# Omitted, not blanked. kubectl's merge treats a missing key and an empty string
# alike ("not set in this file") and falls through to the next entry in
# KUBECONFIG, so an opinionless overlay lets the pane inherit a context from a
# config that genuinely declares it. Empty here means "no opinion", never
# "broken", and it can no longer name something that does not exist.
#
# printf, not a heredoc. `cat` is aliased to bat on the Mac and a sourced file
# inherits the interactive shell's aliases, so `cat > f <<EOF` in this very file
# once produced 0-byte overlays — `>` truncates before bat fails. printf is a
# builtin and cannot be shadowed by PATH at all.
_kube_write_overlay() {
  local ctx=$1 current=""
  [[ -n "$ctx" ]] && current="current-context: ${ctx}"$'\n'
  printf 'apiVersion: v1\nkind: Config\n%scontexts: []\nclusters: []\nusers: []\n' \
    "$current" > "$_KUBE_WINDOW_FILE"
}

# What an existing overlay currently pins, if anything.
_kube_overlay_pinned() {
  [[ -f "$_KUBE_WINDOW_FILE" ]] || return 0
  awk '/^current-context:/ { print $2; exit }' "$_KUBE_WINDOW_FILE" 2>/dev/null
}

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
    _kube_write_overlay "$(_kube_default_context)"
  else
    # Self-heal a survivor. Neither guard above catches an overlay left by an
    # earlier session that pins a since-retired context: the file exists and the
    # init flag is inherited from the tmux server environment, so both say
    # "leave it alone". That is exactly how 23 devbox panes stayed pinned to
    # `orbstack` for the week after it was removed — long-lived panes are the
    # ones that outlive the cluster, so the case that most needs fixing was the
    # one case skipped. If the pinned name is defined nowhere, it is stale by
    # definition; rewrite rather than keep pointing at a cluster that is gone.
    _kube_stale_pin=$(_kube_overlay_pinned)
    if [[ -n "$_kube_stale_pin" ]] && ! _kube_context_exists "$_kube_stale_pin"; then
      _kube_write_overlay "$(_kube_default_context)"
    fi
    unset _kube_stale_pin
  fi

  # Clean up stale overlays older than 7 days
  find "$_KUBE_WINDOW_DIR" -name "*.yaml" -mtime +7 -delete 2>/dev/null
fi
unset _kube_overlay_id

# Build KUBECONFIG: window overlay (receives writes) + all config dirs (read-only)
_kube_build_path() {
  local parts=() f

  # Window overlay first — kubectl writes current-context here
  if [[ -n "$_KUBE_WINDOW_FILE" ]]; then
    parts+=("$_KUBE_WINDOW_FILE")
  fi

  while IFS= read -r f; do parts+=("$f"); done < <(_kube_config_files)

  local IFS=":"
  echo "${parts[*]}"
}

# Set KUBECONFIG on shell startup
export KUBECONFIG="$(_kube_build_path)"

# --- Core ---

# Refresh KUBECONFIG after adding/removing config directories
kube-refresh() {
  export KUBECONFIG="$(_kube_build_path)"
  local ctxs
  ctxs=$(_kube_all_contexts)
  if [[ -z "$ctxs" ]]; then
    echo "KUBECONFIG refreshed. No contexts — nothing under $KUBECONFIG_DIR defines one."
  else
    echo "KUBECONFIG refreshed. Contexts:"
    printf '  %s\n' $ctxs
  fi
}

# Switch context (per-window in kitty, global otherwise)
kube-use() {
  local context=$1
  if [[ -z "$context" ]]; then
    echo "Usage: kube-use <context>"
    echo ""
    kube-list
    return 1
  fi
  kubectl config use-context "$context"
}

# Show current context and config sources
kube-current() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null)
  if [[ -z "$ctx" ]]; then
    echo "Context: (none)"
  elif _kube_context_exists "$ctx"; then
    echo "Context: $ctx"
  else
    # Worth its own line rather than folding into "(none)". These are different
    # faults with different fixes: nothing selected is a choice, whereas a name
    # nothing defines is a pointer left behind by a cluster that went away, and
    # it fails only at the moment you run a real command against it.
    echo "Context: $ctx  [DANGLING — no installed config defines it; kube-clean-overlay]"
  fi
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
  local ctxs f dir defines
  ctxs=$(_kube_all_contexts)
  if [[ -z "$ctxs" ]]; then
    echo "No contexts — nothing under $KUBECONFIG_DIR defines one."
  else
    kubectl config get-contexts 2>/dev/null
  fi
  echo ""
  echo "Config directories:"
  # Reported by the contexts each directory DEFINES, not by its name. A
  # directory name is a filing convention and is not evidence that anything is
  # reachable through it — ~/.kube/configs/kind-iden2-dev on the Mac is a
  # 28-byte stub with zero contexts, and the old `ls` listing advertised it as
  # an available cluster alongside two real ones.
  while IFS= read -r f; do
    dir=$(basename "$(dirname "$f")")
    defines=$(_kube_contexts_in "$f" | tr '\n' ' ')
    if [[ -n "${defines// /}" ]]; then
      printf '  %-22s %s\n' "$dir" "${defines% }"
    else
      printf '  %-22s (defines no contexts)\n' "$dir"
    fi
  done < <(_kube_config_files)
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
  local config_dir="$KUBECONFIG_DIR/kind-$name" tmp
  # Staged through a temp file, and the directory is created only once there is
  # something real to put in it. Writing straight into $config_dir/config means
  # every failure leaves a directory the KUBECONFIG glob will pick up forever.
  tmp=$(mktemp "${TMPDIR:-/tmp}/kubeconfig-kind-XXXXXX") || return 1

  if ! ssh -o ConnectTimeout=15 "$host" "kind get kubeconfig --name '$name'" > "$tmp" 2>/dev/null; then
    echo "Error: could not fetch kubeconfig for '$name' from $host"
    echo "  is the node up?   ts-node k8s status"
    echo "  tailnet ACL must allow tag:devbox -> tag:k8s over ssh and :6443"
    rm -f "$tmp"
    return 1
  fi
  # An empty file here means the ssh hop was refused rather than kind failing --
  # a distinction worth making, because the two look identical downstream.
  if [[ ! -s "$tmp" ]]; then
    echo "Error: empty kubeconfig — the ssh hop to $host probably failed"
    rm -f "$tmp"
    return 1
  fi

  mkdir -p "$config_dir"
  command mv "$tmp" "$config_dir/config"
  chmod 600 "$config_dir/config"
  echo "Kind $name @ $host -> $config_dir/config ($(command grep -m1 'server:' "$config_dir/config" | tr -d ' '))"
  kube-refresh
}

# kind, with whatever container runtime this box actually has.
#
# On the devbox that is rootless podman, reached through the shims in
# ~/.local/share/kind-shims. Sourcing their env.sh is not optional there: it
# exports KIND_EXPERIMENTAL_PROVIDER=podman, and without it kind goes looking
# for docker and reports it as missing even with the docker shim on PATH.
#
# Run in a SUBSHELL so env.sh's PATH surgery and XDG_RUNTIME_DIR override cannot
# leak into the caller's shell, and gated on the file existing rather than on
# $OSTYPE — this file is shared verbatim with the Mac, where the shims are absent
# and plain `kind` is correct. Presence is the better test anyway: it tracks what
# the box has, not what platform it claims to be.
_kube_kind() {
  (
    [[ -f "$HOME/.local/share/kind-shims/env.sh" ]] &&
      . "$HOME/.local/share/kind-shims/env.sh" >/dev/null 2>&1
    command -v kind >/dev/null 2>&1 || return 127
    kind "$@"
  )
}

kube-setup-kind() {
  local name=$1
  if [[ -z "$name" ]]; then
    echo "Usage: kube-setup-kind <cluster-name>"
    echo "Available: $(_kube_kind get clusters 2>/dev/null | tr '\n' ' ')"
    return 1
  fi
  local config_dir="$KUBECONFIG_DIR/kind-$name"

  # Requires the kind CLI. The old fallback -- scraping a `kind-*` context out of
  # ~/.kube/config -- existed only for OrbStack-managed kind, which is gone; with
  # no local container runtime there is nothing for it to find. For a cluster on
  # the k8s node, use kube-setup-kind-remote instead.
  if ! _kube_kind version >/dev/null 2>&1; then
    echo "Error: kind CLI not found. For a remote cluster: kube-setup-kind-remote"
    return 1
  fi

  # mkdir AFTER the export succeeds, not before. Creating it up front leaves an
  # empty directory behind on any failure, and the glob that builds KUBECONFIG
  # cannot tell that apart from a real cluster — which is how the Mac ended up
  # with a kind-iden2-dev/config holding nothing but `apiVersion: v1`.
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/kubeconfig-kind-XXXXXX") || return 1
  if ! _kube_kind export kubeconfig --name "$name" --kubeconfig "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if [[ -z "$(_kube_contexts_in "$tmp")" ]]; then
    echo "Error: kind exported a kubeconfig defining no contexts — not installing it."
    rm -f "$tmp"
    return 1
  fi
  mkdir -p "$config_dir"
  command mv "$tmp" "$config_dir/config"
  chmod 600 "$config_dir/config"
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
  # Preserve where you are — but only if that is still a real place. The old
  # fallback (`|| echo "$KUBE_DEFAULT_CONTEXT"`) re-stamped the unvalidated
  # default, so the one command whose job is to clear a bad overlay could write
  # the bad value straight back in.
  local current
  current=$(kubectl config current-context 2>/dev/null)
  _kube_context_exists "$current" || current=$(_kube_default_context)
  _kube_write_overlay "$current"
  echo "Cleaned $_KUBE_WINDOW_FILE (current-context=${current:-<none>})."
}

# Drop every overlay pinning a context nothing defines, across all panes.
#
# The self-heal at the top of this file only ever fixes the pane it runs in,
# which is right for a shell and useless for a converge step: after a cluster is
# retired, the other 22 panes stay wrong until each is next used. restore.sh
# calls this to sweep them in one pass.
#
# Deleted rather than rewritten. An overlay is per-pane, disposable state -- the
# next shell in that pane builds a fresh one -- so removing it is both simpler
# and the correct semantics: the pane has no opinion any more.
kube-prune-overlays() {
  local dir="${KUBECONFIG_DIR}/.window-overlays" f pinned n=0
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.yaml; do
    [[ -f "$f" ]] || continue
    pinned=$(awk '/^current-context:/ { print $2; exit }' "$f" 2>/dev/null)
    [[ -z "$pinned" ]] && continue
    if ! _kube_context_exists "$pinned"; then
      rm -f "$f"
      n=$((n + 1))
    fi
  done
  [[ "$n" -gt 0 ]] && echo "pruned $n window overlay(s) pinning a context nothing defines"
  return 0
}

# Refresh kind config after a cluster recreate (new CA + maybe new port).
# Combines: re-export to dedicated file + clean window overlay.
# Run after `task switch:kind` or `task kind:up` if you hit
# "TLS verify failed" or "connection refused" from kubectl.
kube-refresh-kind() {
  local name=${1:-iden2-dev}
  if ! _kube_kind get clusters 2>/dev/null | command grep -q "^${name}$"; then
    echo "Kind cluster '${name}' not found. Available: $(_kube_kind get clusters 2>/dev/null | tr '\n' ' ')"
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
  COMPREPLY=($(compgen -W "$(_kube_all_contexts)" -- "$cur"))
}
complete -F _kube_use_completions kube-use

_kube_setup_kind_completions() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "$(_kube_kind get clusters 2>/dev/null)" -- "$cur"))
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
