output "label" {
  description = "Linode label / Tailscale hostname"
  value       = linode_instance.exit_node.label
}

output "ipv4" {
  description = "Public IPv4 (informational — connect via Tailscale, not this)"
  value       = try(tolist(linode_instance.exit_node.ipv4)[0], null)
}

output "instance_id" {
  description = "Linode instance ID — used by ts-exit start/stop"
  value       = linode_instance.exit_node.id
}

output "post_apply_steps" {
  description = "What to do next"
  value       = <<-EOT

    ── Pick ${linode_instance.exit_node.label} as exit node in the Tailscale app ──
    (autoApprover ACL rule already approved exit-node advertisement on join)

    ── SSH in via Tailscale ──
    ./ts-exit ssh

  EOT
}
