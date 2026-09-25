# VPC
resource "google_compute_network" "vpc_network" {
  name                    = "terraform-demo-network"
  auto_create_subnetworks = false
}

#Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

#cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone

  deletion_protection = false

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnet.id
}

#node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 25

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]
    preemptible = true
    metadata    = { disable-legacy-endpoints = "true" }

  }
}

resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "gke-demo-repo"
  format        = "DOCKER"
}

