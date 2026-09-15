output "label" {
  description = "Vultr label / Tailscale hostname"
  value       = vultr_instance.node.label
}

output "instance_id" {
  description = "Vultr instance UUID — the only stable identifier, since labels are not unique"
  value       = vultr_instance.node.id
}

output "ipv4" {
  description = "Public IPv4 — informational only; connect over Tailscale, never this"
  value       = vultr_instance.node.main_ip
}

output "role" {
  description = "Node role"
  value       = var.role
}

output "teardown_check" {
  description = <<-EOT
    The command that proves a destroy actually happened.

    Measured 2026-09-15: DELETE on an instance that is still provisioning returns
    409 while `status` already reads "active" — the blocking field is
    `server_status: locked`. A retry 12s later returned 204. So a teardown that
    trusts one call, or trusts its exit code, leaves an instance running and
    billing with nothing on screen to say so.

    Destroy is the only thing that stops charges here — a stopped Vultr instance
    bills in full — which is what makes a silent leak expensive rather than
    untidy. Confirm by fetching, never by the status code.

    Addressed by UUID, not by label. An earlier version of this output filtered
    `instance list` on the label, which contradicts the reason this module
    exists: labels are not unique on Vultr, so a label match cannot tell you
    WHICH instance survived, and a second box wearing the same label reads as
    the first one having failed to die. A 404 on the UUID is the only
    unambiguous proof.
  EOT
  value       = "vultr-cli instance get ${vultr_instance.node.id} # expect 404 after destroy"
}
