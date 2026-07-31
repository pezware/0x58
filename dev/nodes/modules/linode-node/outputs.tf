output "label" {
  description = "Linode label / Tailscale hostname"
  value       = linode_instance.node.label
}

output "instance_id" {
  description = "Linode instance ID — used by ts-node start/stop/status"
  value       = linode_instance.node.id
}

output "ipv4" {
  description = "Public IPv4 — informational only; connect over Tailscale, never this"
  value       = try(tolist(linode_instance.node.ipv4)[0], null)
}

output "role" {
  description = "Node role"
  value       = var.role
}
