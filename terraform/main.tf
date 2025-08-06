# Generate a random suffix for resource names to avoid conflicts
resource "random_id" "suffix" {
  byte_length = 4
}

# Reserve a static external IP address
resource "google_compute_address" "static_ip" {
  name    = "portfolio-static-ip-${random_id.suffix.hex}"
  project = var.project_id
}

# Create a service account for registry authentication
resource "google_service_account" "registry_account" {
  account_id   = "portfolio-auth-sa"
  display_name = "Service Account for Portfolio Authentication"
  project      = var.project_id
}

# Create a service account key for registry authentication
resource "google_service_account_key" "registry_key" {
  service_account_id = google_service_account.registry_account.email
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

# Create a compute instance
resource "google_compute_instance" "container_vm" {
  name         = var.instance_name
  machine_type = "e2-small"
  zone         = var.zone
  project      = var.project_id
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  network_interface {
    network    = var.network_name
    subnetwork = var.subnetwork_name
    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  tags = ["http-server", "https-server", "ssh"]

  metadata = {}

  labels = {
    environment = "production"
    managed-by  = "terraform"
    service     = "portfolio"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}

# Create a firewall rule to allow HTTP/HTTPS traffic
resource "google_compute_firewall" "allow_http_https" {
  name    = "portfolio-allow-http-https"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}

# Create a firewall rule to allow SSH traffic
resource "google_compute_firewall" "allow_ssh" {
  name    = "portfolio-allow-ssh"
  network = var.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh"]
}

# Create a health check
resource "google_compute_health_check" "http_health_check" {
  name               = "portfolio-health-check"
  timeout_sec        = 5
  check_interval_sec = 10
  project            = var.project_id

  http_health_check {
    port = 80
    request_path = "/health"
  }
} 
