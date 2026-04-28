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

function kube_ps1() {
  local context=$(kubectl config current-context 2>/dev/null)
  local namespace=$(kubectl config view --minify 2>/dev/null | grep namespace | cut -d' ' -f6)

  # Extract just the cluster name from EKS ARNs
  if [[ "$context" == arn:aws:eks:* ]]; then
    # Extract the cluster name after 'cluster/'
    context=$(echo "$context" | sed 's/.*cluster\///')
  fi

  if [ -n "$context" ]; then
    # Red for admin contexts (visual safety cue), blue for everything else
    if [[ "$context" == *-admin* ]]; then
      local RED=$'\001\e[01;31m\002'
      echo "${RED}[$context:$namespace]${COLOR_NONE} "
    else
      echo "${BLUE}[$context:$namespace]${COLOR_NONE} "
    fi
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
