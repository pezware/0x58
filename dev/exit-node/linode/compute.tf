# Random root password — required by the Linode API but never used.
# Tailscale SSH is the only access path; OpenSSH is disabled in bootstrap.sh.
resource "random_password" "root" {
  length  = 32
  special = false
}

resource "linode_instance" "exit_node" {
  label  = var.label
  region = var.region
  type   = var.type
  image  = "linode/debian12"

  root_pass = random_password.root.result

  tags = ["tailscale", "exit-node"]

  metadata {
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      tailscale_auth_key = var.tailscale_auth_key
      hostname           = var.label
      bootstrap_script   = file("${path.module}/bootstrap.sh")
    }))
  }

  # No private_ip — exit node only needs public IPv4/IPv6.
  # Public IP is the default; firewall (below) gates inbound traffic.
}

# Cloud Firewall: replicates GCP's deny-all-ingress + allow-all-egress posture.
# Without this, the Nanode's public IP is reachable on every port the OS happens to listen on.
resource "linode_firewall" "exit_node" {
  label = "${var.label}-fw"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  # Empty inbound — Tailscale punches through outbound only via DERP/STUN.
  # Outbound default ACCEPT is parity with GCP allow-all-egress.

  linodes = [linode_instance.exit_node.id]
}
