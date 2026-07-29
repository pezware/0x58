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

  label = "pezware-k8s"
  role  = "k8s"

  # g6-standard-2: 2 vCPU / 4 GB / 80 GB / $24 mo, but billed hourly at
  # ~$0.036 — the point of this role is that it exists only while in use.
  type = "g6-standard-2"

  tailscale_auth_key = var.tailscale_auth_key
  tailscale_tag      = "tag:k8s"

  # MUST be 0. kubelet refuses to start when swap is enabled, and kind's
  # node containers run a real kubelet.
  swap_mb = 0

  bootstrap_script = file("${path.module}/bootstrap.sh")
  extra_tags       = ["ephemeral"]
}

output "label" { value = module.node.label }
output "instance_id" { value = module.node.instance_id }
output "ipv4" { value = module.node.ipv4 }

output "post_apply_steps" {
  value = <<-EOT

    ── import the cluster into the devbox (run there, or from the Mac) ──
    mkdir -p ~/.kube/configs/kind-dev
    ssh ${module.node.label} 'kind get kubeconfig --name dev' > ~/.kube/configs/kind-dev/config
    kube-refresh && kube-use kind-dev

    ── tear down when finished — only destroy stops the billing ──
    ./ts-node k8s destroy

  EOT
}
