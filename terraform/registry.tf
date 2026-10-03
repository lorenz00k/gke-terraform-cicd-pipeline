#Artifact registry repository
resource "google_artifact_registry_repository" "repo" {
  # checkov:skip=CKV_GCP_84: Google-managed encryption is sufficient for me
  location      = var.region
  repository_id = "gke-demo-repo"
  format        = "DOCKER"
}
