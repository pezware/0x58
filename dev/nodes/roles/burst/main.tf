terraform {
  required_version = ">= 1.10" # use_lockfile — see backend.tf
  required_providers {
    vultr = { source = "vultr/vultr", version = "~> 2.32" }
  }
}

# VULTR_API_KEY from the environment, never a variable — a provider credential
# passed as a variable reaches tfstate. ts-node sources it from
# ~/.config/0x58/credentials.env on whichever controller is driving.
provider "vultr" {}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

variable "plan" {
  description = <<-EOT
    Overridable so a session can buy the width it needs and no more. Cost is
    per hour and the box is destroyed at the end, so this is the one knob worth
    thinking about before an apply:

      vhp-8c-16gb    8 vCPU / 16 GB   $0.132/hr   default — kind + the suite
      vhp-12c-24gb  12 vCPU / 24 GB   $0.197/hr   wide builds

    Pick it correctly the FIRST time. Vultr upgrades in place and never
    downgrades, so a box provisioned small cannot be widened cheaply and a box
    provisioned wide bills that rate until it is destroyed.
  EOT
  type        = string
  default     = "vhp-8c-16gb"
}

# The disposable build box. Created at full size, used, destroyed.
#
# This replaces the Linode floor-and-resize loop rather than porting it. Vultr
# cannot return to a floor, so there is nothing to park at: every session pays
# only for the hours it runs, and `destroy` is the only thing that ends the bill
# -- a stopped Vultr instance is charged in full.
module "node" {
  source = "../../modules/vultr-node"

  label = "pezware-burst"
  role  = "burst"

  plan               = var.plan
  tailscale_auth_key = var.tailscale_auth_key

  # tag:burst, and it must be a DEAD END in the ACL.
  #
  # This box runs other people's build code. The cached auth key is readable by
  # that workload -- an accepted risk, recorded in #106 -- and Vultr's metadata
  # service re-serves user_data to anything on the instance, so no scrubbing
  # closes it. What contains the blast radius is the policy: tag:burst reaches
  # NOTHING. Not the controllers, not the devbox, not the tailnet at large.
  #
  # Which is also why this must be handed a SINGLE-USE key, never the reusable
  # tag:k8s key that roles/k8s keeps for rebuild ergonomics. A single-use key is
  # spent the moment this node joins, so the copy the workload can read is
  # already worthless.
  tailscale_tag = "tag:burst"

  # Swap earns its place during builds: a Kotlin compile that overshoots should
  # get slow, not get OOM-killed. An OOM loses the whole build and reads as a
  # flaky test.
  #
  # Allowed because kind's kubelet sets failSwapOn: false. A native kubelet
  # refuses to start with swap, which is what the module precondition guards
  # for role == "k8s".
  swap_mb = 4096

  # MUST stay 0 — common.sh discovers volumes at a hard-coded Linode device
  # path. Nothing here is worth keeping anyway: the repo, the credentials and
  # the git history all live on the controller.
  volume_gb = 0

  common_script    = file("${path.module}/../../modules/linode-node/common.sh")
  bootstrap_script = file("${path.module}/bootstrap.sh")
  extra_tags       = ["ephemeral", "build"]
}

output "label" { value = module.node.label }
output "instance_id" { value = module.node.instance_id }
output "ipv4" { value = module.node.ipv4 }
output "teardown_check" { value = module.node.teardown_check }

output "post_apply_steps" {
  value = <<-EOT

    ── send it code — it can fetch none of its own ──
    rsync -e 'tailscale ssh' -a ~/src/iden2/<repo>/ ${module.node.label}:~/src/<repo>/

    ── import the cluster ──
    tailscale ssh ${module.node.label} 'kind get kubeconfig --name dev' \
      > ~/.kube/configs/kind-burst/config && kube-refresh && kube-use kind-burst

    ── WHEN FINISHED. Only destroy stops the billing ──
    ./ts-node burst destroy

    Then CONFIRM it, because the delete can fail quietly: DELETE on an instance
    that is still provisioning returns 409 while status already reads "active".
    ts-node retries, but verify anyway —

      ${module.node.teardown_check}

  EOT
}
