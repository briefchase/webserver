variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone to deploy resources"
  type        = string
  default     = "us-central1-a"
}

variable "instance_name" {
  description = "The name of the VM instance"
  type        = string
  default     = "portfolio"
}

variable "network_name" {
  description = "The name of the VPC network to use"
  type        = string
  default     = "default"
}

variable "subnetwork_name" {
  description = "The name of the subnetwork to use"
  type        = string
  default     = "default"
}

variable "gcp_region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1" # Example default, adjust if needed
}

variable "vm_zone" {
  description = "The GCP zone for the VM instance"
  type        = string
  default     = "us-central1-a" # Example default, adjust if needed
}

variable "vm_machine_type" {
  description = "The machine type for the VM instance"
  type        = string
  default     = "e2-medium" # Example default, adjust if needed
}

variable "ssh_user" {
  description = "The username for SSH access to the VM"
  type        = string
  default     = "sshuser" # Example default username
}
