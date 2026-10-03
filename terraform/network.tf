# VPC
resource "google_compute_network" "vpc_network" {
  name                    = "terraform-demo-network"
  auto_create_subnetworks = false
}

# firewall
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-firewall"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # only traffic from inside the subnet
  source_ranges = [google_compute_subnetwork.subnet.ip_cidr_range]
}

#Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id

  private_ip_google_access = true

  # Network traffic metadata for troubleshooting / auditing
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}