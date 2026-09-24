variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources (e.g. subnetwork)"
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "The GCP zone for zonal resources (e.g. the cluster itself)"
  type        = string
  default     = "europe-west3-a"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "gke-demo-cluster"
}

variable "machine_type" {
  description = "Machine type for the GKE nodes"
  type        = string
  default     = "e2-medium"
}

variable "node_count" {
  description = "Number of nodes in the node pool"
  type        = number
  default     = 1
}