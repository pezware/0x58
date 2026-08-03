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

  # g6-standard-4: 4 vCPU / 8 GB / 160 GB, billed hourly at ~$0.072 — the point
  # of this role is that it exists only while in use, so a 3-hour session is
  # about $0.22 and cost is not the binding constraint.
  #
  # 8 GB, not 4. The earlier "4 GB comfortably fits one node" was true of an
  # EMPTY kind cluster and misleading for anything real: the iden2 stack needs
  # eight local image builds plus Traefik, Vault, Redis, Postgres, Keycloak,
  # three walt.id services and five iden2 services. For full CI parity the
  # target is g6-standard-6 (6 vCPU / 16 GB), matching GitHub's 4 vCPU / 16 GB
  # ubuntu-latest — worth revisiting when the runner work happens.
  type = "g6-standard-4"

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
