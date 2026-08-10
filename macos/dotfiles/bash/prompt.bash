#### bash prompt ####
GRAY="\e[2;37m"
BLUE="\e[1;34m"
GREEN="\e[0;32m"
PURPLE="\e[1;35m"
COLOR_NONE="\e[0m"

COLOR_NONE=$'\001\e[0m\002'               # Default
GRAY=$'\001\e[01;37m\002'
BLUE=$'\001\e[01;34m\002'
GREEN=$'\001\e[01;32m\002'
PURPLE=$'\001\e[00;35m\002'


# Detect whether the current directory is a git repository.
function is_git_repository() {
  git branch > /dev/null 2>&1
}

function set_git_branch () {
    # Note that for new repo without commit, git rev-parse --abbrev-ref HEAD
    # will error out.
    if git rev-parse --abbrev-ref HEAD > /dev/null 2>&1; then
        BRANCH=$(git rev-parse --abbrev-ref HEAD)
    else
        BRANCH="bare repo!"
    fi
}

# How the prompt renders a context that is SET but that no config defines.
#
# This state used to be invisible: it rendered exactly like a healthy context,
# in the same blue, which is how 23 devbox panes spent a week claiming
# `[orbstack:]` while every kubectl call against it failed. The shell now
# self-heals its own pane at startup, so this should be rare — but "rare" is
# precisely when a silent wrong answer does the most damage, and a context can
# still go stale mid-session when a cluster is deleted under a live pane.
#
# Worth noting before choosing: red is already taken, and it means something
# specific here — *-admin contexts are red because they are DANGEROUS, i.e. the
# commands will work, against staging-admin. A dangling context is the opposite:
# nothing will work at all. Reusing red for both makes the strong signal weaker.
#
#   $1 — the label already assembled, "context" or "context:namespace"
#   stdout — the prompt segment, including a trailing space, or nothing at all
#
# TODO(andy): replace the placeholder below with the rendering you want.
function kube_ps1_dangling() {
  local label=$1
  echo "${BLUE}[$label]${COLOR_NONE} "
}

# Kubernetes segment of the prompt. Three states, not two: no context at all
# (print nothing), a context this machine defines (normal or the admin cue), and
# a context defined nowhere (kube_ps1_dangling, above).
function kube_ps1() {
  local context namespace label
  context=$(kubectl config current-context 2>/dev/null)

  # No context is a legitimate state — a fresh pane on a box with nothing
  # installed — and the prompt says nothing at all about Kubernetes. It must not
  # invent a placeholder: an empty prompt segment is the honest report.
  [ -n "$context" ] || return 0

  # Extract just the cluster name from EKS ARNs
  if [[ "$context" == arn:aws:eks:* ]]; then
    context=${context##*cluster/}
  fi

  # jsonpath rather than `grep namespace | cut -d' ' -f6`. Counting spaces in
  # kubectl's YAML meant the field position was load-bearing, so any change in
  # indentation silently yields the wrong word — the same class of bug that made
  # the context parser in kubectl-context.bash miss gke-stg-admin.
  namespace=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)

  # No trailing colon when there is no namespace. "[gke-stg-ro:]" reads like a
  # value failed to load rather than like there is simply nothing to show.
  label="$context"
  [ -n "$namespace" ] && label="$context:$namespace"

  # _kube_context_exists lives in kubectl-context.bash, which ~/.bashrc sources
  # AFTER this file. Harmless — nothing here runs until PROMPT_COMMAND fires, by
  # which point both are loaded — but guarded so the prompt cannot break on a
  # machine that has one file and not the other. Costs ~2.6ms against the ~50ms
  # the two kubectl calls above already spend, so it needs no caching.
  if declare -F _kube_context_exists >/dev/null 2>&1 && ! _kube_context_exists "$context"; then
    kube_ps1_dangling "$label"
    return 0
  fi

  # Red for admin contexts (visual safety cue), blue for everything else
  if [[ "$context" == *-admin* ]]; then
    local RED=$'\001\e[01;31m\002'
    echo "${RED}[$label]${COLOR_NONE} "
  else
    echo "${BLUE}[$label]${COLOR_NONE} "
  fi
}


function set_bash_prompt () {

    if is_git_repository; then
        set_git_branch
    else
        BRANCH=''
    fi

    PS1=""
    # set up user and host
    PS1+="${GRAY}\u@\h${COLOR_NONE} "
    # set up working directory
    PS1+="${GREEN}\w${COLOR_NONE} "
    # set up kubernetes context (kube_ps1 handles its own color for admin contexts)
    PS1+="$(kube_ps1)"
    # set up git branch
    PS1+="${GRAY}${BRANCH}${COLOR_NONE}\n#"
    # set up prompt character
    PS1+="${PURPLE}>${COLOR_NONE} "
}


export PROMPT_COMMAND=set_bash_prompt
#until [ ! -z "$MCHOICE" ]; do
#        read -p "${OPROMPT} " -e MCHOICE
#done
