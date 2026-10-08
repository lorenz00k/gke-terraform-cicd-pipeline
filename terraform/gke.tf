#cluster
resource "google_container_cluster" "primary" {
  # checkov:skip=CKV_GCP_65: RBAC via Google Groups needs a Google Workspace group
  # checkov:skip=CKV_GCP_64: Private nodes would need Cloud NAT; the deploy pipeline also needs to reach the API server
  # checkov:skip=CKV_GCP_25: Private cluster would block GitHub Actions runners (dynamic IPs) from running kubectl
  # checkov:skip=CKV_GCP_20: Master authorized networks would block GitHub Actions runners (dynamic IPs)
  # checkov:skip=CKV_GCP_69: Rule inspects the cluster's default node pool, which is removed; the real node pool sets GKE_METADATA
  # checkov:skip=CKV_GCP_66: Binary Authorization needs attestors and policies
  # checkov:skip=CKV_GCP_61: pod-level traffic on worker node currently not needed
  name     = var.cluster_name
  location = var.zone

  resource_labels = {
    environment = "development"
    team       = "lo"
  }

  deletion_protection = false

  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {} # vpc-native cluster: alias IP ranges enabled -> allow pods to directly access hosted services without using NAT gateway

  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnet.id

  # no pods and services can access each other from another namespace
  network_policy {
    enabled = true
  }

  # Pods get their own identity instead of the node's credentials
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }


  # don't issue client certificates for authentication
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Receive upgrades automatically from Google's REGULAR channel
  release_channel {
    channel = "REGULAR"
  }
}

#node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  # Repair broken nodes and keep them on a supported version
  management {
    auto_repair  = true
    auto_upgrade = true
  }

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

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}