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

  label = "pezware-waltid"
  role  = "waltid"

  # g6-dedicated-8: 8 vCPU / 16 GB / 320 GB, $0.216/hr (~$5.18/day).
  #
  # DEDICATED, not standard, and the reason is the workload's shape rather than
  # its peak. A walt.id Gradle build holds every core at 100% for minutes at a
  # time, and this box is expected to do that for days. Linode's shared plans
  # share a physical core with other tenants, so sustained full load is where
  # they lose time to steal; a dedicated plan does not.
  #
  # 16 GB is the floor, not comfort: the Gradle daemon, the Kotlin compile
  # daemon and a docker image build are three JVMs and a builder resident at
  # once. roles/k8s/main.tf already names 16 GB as the CI-parity target,
  # matching GitHub's 4 vCPU / 16 GB ubuntu-latest.
  type = "g6-dedicated-8"

  tailscale_auth_key = var.tailscale_auth_key

  # tag:k8s, DELIBERATELY, though this node runs no cluster.
  #
  # The tag is reused so the handoff needs no Tailscale admin work: the policy
  # already grants `tag:devbox -> tag:k8s:6443,22` and an SSH rule for the same
  # pair, which is exactly the path the waltid agent needs. A tag:waltid would
  # be more honest and would cost a minted key plus an ACL edit in the browser
  # before the agent could reach anything.
  #
  # The trade is real and bounded: this node inherits the k8s tag's blast
  # radius, so a rule written for throwaway cluster nodes also applies here.
  # Both are disposable build boxes holding no credentials, so the classes
  # match. Split the tag if this box ever holds a secret.
  tailscale_tag = "tag:k8s"

  # 4 GB of swap, which the k8s role must NOT have and this one wants.
  #
  # No kubelet runs here, so the constraint that forces swap_mb = 0 on k8s does
  # not apply. What applies instead is that a Kotlin compile that overshoots 16
  # GB should get slow rather than get killed: an OOM kill loses the whole build
  # and reads as a flaky test, while swapping loses minutes and says so.
  # Sized as a safety net, not as usable memory -- if builds live in swap, the
  # answer is a bigger plan, not a bigger swapfile.
  swap_mb = 4096

  # Linode's own 512 MB swap partition, left at its default on purpose. It is
  # additive to the swapfile above and harmless without a kubelet.
  linode_swap_mb = 512

  # No Block Storage volume, on purpose. 320 GB of root disk holds the Gradle
  # caches, the container images and the working trees for a session measured in
  # days, and linode_volume.data carries prevent_destroy -- which turns the
  # teardown this node exists to have into a two-step manual state edit. Nothing
  # here is worth keeping: the repo and the credentials stay on the devbox.
  volume_gb = 0

  bootstrap_script = file("${path.module}/bootstrap.sh")
  extra_tags       = ["ephemeral"]
}

output "label" { value = module.node.label }
output "instance_id" { value = module.node.instance_id }
output "ipv4" { value = module.node.ipv4 }

output "post_apply_steps" {
  value = <<-EOT

    ── 1. give the devbox a NAME for it (MagicDNS does not resolve here) ──
    These nodes run `tailscale up --accept-dns=false`, so the devbox cannot
    resolve pezware-waltid. Pin the tailnet IP in the devbox's ~/.ssh/config:

      Host pezware-waltid waltid
          HostName <the ipv4 output below, tailnet address from `tailscale ip -4`>
          User arbeitandy

    ── 2. seed the repo (run on the devbox) ──
    Push the PARENT repo, not a worktree: a worktree's .git is a FILE pointing
    into the parent, so it arrives as a broken repo on its own. rsync is
    incremental, so later re-syncs send only what changed.

      rsync -a ~/src/iden2/waltid-identity-mirror/ waltid:~/src/waltid-identity-mirror/
      ssh waltid 'cd ~/src/waltid-identity-mirror && git worktree prune && git checkout <sha>'

    ── 3. build ──
      ssh waltid build-env                        # toolchain, with versions
      ssh waltid -t tmux attach -t main           # long builds go in tmux

    ── tear down when the PRs are done — only destroy stops the billing ──
    ./ts-node waltid destroy

  EOT
}
