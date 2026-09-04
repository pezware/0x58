terraform {
  required_version = ">= 1.6"
  required_providers {
    linode = { source = "linode/linode", version = "~> 2.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "linode" {}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

module "node" {
  source = "../../modules/linode-node"

  # ONE testbox exists at a time, and this label is what enforces it. Linode
  # labels are unique per account, so a second apply against a live node is
  # refused by the API rather than by anyone remembering the rule. `ts-node`
  # also checks the label before planning, so the refusal explains itself
  # instead of surfacing as a provider error.
  label = "pezware-testbox"
  role  = "testbox"

  # THE FLOOR, and the one number here that cannot be changed later.
  #
  # Linode grows disks but never shrinks them, the module pins
  # resize_disk = false, and ts-node sends allow_auto_disk_resize=false. So the
  # disk is fixed at creation at this plan's allotment -- 160 GB -- forever.
  # Two consequences follow, and both are why this is g6-standard-4 rather than
  # the plan the box usually runs at:
  #
  #   1. This is the cheapest state it can return to: $0.072/hr parked, against
  #      $0.144 for a standard-6 floor.
  #   2. Resize duration tracks the disk ALLOCATION, not its usage, at ~107
  #      MB/s (measured on pezware-cuatro, 2026-08-11). 160 GB is ~25 minutes;
  #      a 320 GB floor would be ~51.
  #
  # Resize UP freely -- every larger plan allows a 160 GB disk:
  #   test     g6-standard-6    6 vCPU / 16 GB   $0.144/hr
  #   build    g6-standard-8    8 vCPU / 32 GB   $0.288/hr
  #   CPU-heavy g6-dedicated-8  8 vCPU / 16 GB   $0.216/hr
  #
  # Resize at SPIKE boundaries, never per build. A build measured 6m56s; a
  # resize is ~25 minutes each way AND reboots the box, which does not bring
  # containers back on its own.
  type = "g6-standard-4"

  tailscale_auth_key = var.tailscale_auth_key

  # tag:k8s, reused deliberately. The policy already grants
  # `tag:devbox -> tag:k8s:6443,22`, which is exactly what this box needs: 22 to
  # drive it, 6443 so a devbox agent can reach the kind API server. Port 6443
  # was in the policy before this role existed -- clusters were always meant to
  # live out here.
  tailscale_tag = "tag:k8s"

  # Swap is allowed here because the kubelet that runs on this box is KIND's,
  # and kind sets failSwapOn: false. A native kubelet would refuse to start,
  # which is why roles/k8s pins this to 0 and the module has a precondition for
  # that role alone. The swapfile earns its place during builds: a Kotlin
  # compile that overshoots should get slow, not get OOM-killed, because an OOM
  # loses the whole build and reads as a flaky test.
  swap_mb = 4096

  # Linode's own swap partition, additive to the swapfile above.
  linode_swap_mb = 512

  # No Block Storage volume. The floor plan is cheap enough that destroy and
  # rebuild is the intended lifecycle, and linode_volume.data carries
  # prevent_destroy -- which would turn every teardown into a two-step manual
  # state edit. Nothing here is worth keeping: the repo, the credentials and
  # the git history all live on the devbox.
  volume_gb = 0

  bootstrap_script = file("${path.module}/bootstrap.sh")
  extra_tags       = ["ephemeral", "singleton"]
}

output "label" { value = module.node.label }
output "instance_id" { value = module.node.instance_id }
output "ipv4" { value = module.node.ipv4 }

output "post_apply_steps" {
  value = <<-EOT

    ── 1. claim it, so the next agent knows it is taken ──
    testbox claim <agent> "<what you are doing>"
    testbox status                       # holder, uptime, cost, queue depth

    ── 2. send it code (from the devbox; it cannot fetch any) ──
    rsync -e sandbox-ssh -a ~/src/iden2/<repo>/ testbox:~/src/<repo>/

    ── 3. resize for a build spike, then come back down ──
    ./ts-node testbox resize g6-standard-8    # ~25 min, reboots at the end
    ./ts-node testbox resize g6-standard-4    # the floor

    ── 4. when finished ──
    testbox release      # hands to the next in queue, or tells you to destroy
    ./ts-node testbox destroy               # ONLY this stops the billing

  EOT
}
