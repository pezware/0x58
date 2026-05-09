terraform {
  required_version = ">= 1.6"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Token comes from LINODE_TOKEN env var, set by the ts-exit wrapper from macOS Keychain.
# Never declared as a variable so it can't accidentally land in tfstate or a tfvars file.
provider "linode" {}
