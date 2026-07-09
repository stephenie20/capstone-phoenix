output "control_plane_public_ip" {
  description = "Public IP of the k3s control plane node"
  value       = module.compute.control_plane_public_ip
}

output "control_plane_private_ip" {
  description = "Private IP of the k3s control plane (used by workers to join)"
  value       = module.compute.control_plane_private_ip
}

output "worker_public_ips" {
  description = "Public IPs of the k3s worker nodes"
  value       = module.compute.worker_public_ips
}

output "worker_private_ips" {
  description = "Private IPs of the k3s worker nodes"
  value       = module.compute.worker_private_ips
}

# Ansible inventory rendered from outputs — paste into infra/ansible/inventory/hosts.ini
output "ansible_inventory" {
  description = "Ready-to-paste Ansible inventory block"
  value       = <<-EOT
    [control_plane]
    ${module.compute.control_plane_public_ip} ansible_user=ubuntu

    [workers]
    %{for ip in module.compute.worker_public_ips~}
    ${ip} ansible_user=ubuntu
    %{endfor~}

    [k3s_cluster:children]
    control_plane
    workers
  EOT
}
