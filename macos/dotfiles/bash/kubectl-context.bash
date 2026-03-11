#!/bin/bash

# Kubernetes context management functions

# Base directory for kubeconfig files
KUBECONFIG_DIR="${HOME}/.kube/configs"

# Function to switch kubectl context
kube-use() {
    local context=$1

    if [ -z "$context" ]; then
        echo "Usage: kube-use <context>"
        echo "Available contexts:"
        ls -1 "$KUBECONFIG_DIR"
        return 1
    fi

    local config_file="$KUBECONFIG_DIR/$context/config"

    if [ ! -f "$config_file" ]; then
        echo "Error: Config file not found for context '$context'"
        echo "Available contexts:"
        ls -1 "$KUBECONFIG_DIR"
        return 1
    fi

    export KUBECONFIG="$config_file"
    echo "Switched to $context context"

    # Show current context
    kubectl config current-context
}

# Function to show current context
kube-current() {
    if [ -z "$KUBECONFIG" ]; then
        echo "No KUBECONFIG set. Using default config."
        kubectl config current-context
    else
        echo "KUBECONFIG: $KUBECONFIG"
        kubectl config current-context
    fi
}

# Function to list available contexts
kube-list() {
    echo "Available kubeconfig contexts:"
    ls -1 "$KUBECONFIG_DIR"
    echo
    echo "Current KUBECONFIG: ${KUBECONFIG:-default}"
}

# Function to set up EKS config
kube-setup-eks() {
    local env=$1
    local cluster_name=$2
    local region=$3

    if [ -z "$env" ] || [ -z "$cluster_name" ]; then
        echo "Usage: kube-setup-eks <env> <cluster-name> [region]"
        echo "Example: kube-setup-eks dev my-cluster us-east-1"
        return 1
    fi

    local config_file="$KUBECONFIG_DIR/eks-$env/config"

    # Create directory if it doesn't exist
    mkdir -p "$KUBECONFIG_DIR/eks-$env"

    # Use AWS CLI to update config
    KUBECONFIG="$config_file" aws eks update-kubeconfig \
        --name "$cluster_name" \
        --region "${region:-eu-central-2}" \
        --alias "eks-$env"

    echo "EKS config for $env environment saved to $config_file"
}

# Convenience aliases
alias k='kubectl'
alias kc='kube-current'
alias kl='kube-list'

# Auto-completion for kube-use function
_kube_use_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local contexts=$(ls -1 "$KUBECONFIG_DIR" 2>/dev/null)
    COMPREPLY=($(compgen -W "$contexts" -- "$cur"))
}
complete -F _kube_use_completions kube-use

# Default to orbstack on startup (optional)
export KUBECONFIG="$KUBECONFIG_DIR/orbstack/config"

# Wrapper for cluster-switcher
eks-switch() {
    local env=$1
    if [ -z "$env" ]; then
        echo "Usage: eks-switch <dev|stg|prd>"
        return 1
    fi

    # Run cluster-switcher and capture its output
    local output
    output=$(cluster-switcher "$env" 2>&1)
    local exit_code=$?

    # Show the output
    echo "$output"

    # If successful, extract and set environment variables
    if [ $exit_code -eq 0 ]; then
        # Extract AWS_PROFILE from output
        local aws_profile=$(echo "$output" | grep "AWS_PROFILE environment variable set to:" | awk '{print $NF}')
        # Extract KUBECONFIG from output
        local kubeconfig=$(echo "$output" | grep "KUBECONFIG environment variable set to:" | awk '{print $NF}')

        # Set the variables if found
        if [ -n "$aws_profile" ]; then
            export AWS_PROFILE="$aws_profile"
        fi
        if [ -n "$kubeconfig" ]; then
            export KUBECONFIG="$kubeconfig"
        fi
    fi

    return $exit_code
}
