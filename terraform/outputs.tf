output "instance_ip" {
  description = "The public IP address of the instance"
  value       = google_compute_instance.container_vm.network_interface[0].access_config[0].nat_ip
}

output "instance_name" {
  description = "The name of the instance"
  value       = google_compute_instance.container_vm.name
}

output "instance_public_ip" {
  description = "The public IP address of the compute instance."
  value       = google_compute_instance.container_vm.network_interface[0].access_config[0].nat_ip
}

output "instance_zone" {
  description = "The zone of the compute instance."
  value       = google_compute_instance.container_vm.zone
} 