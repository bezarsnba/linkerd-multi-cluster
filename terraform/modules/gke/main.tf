resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  deletion_protection = false
  initial_node_count = var.initial_nodes

  node_config {
    machine_type = var.machine_type
    disk_type    = "pd-standard"
    disk_size_gb = var.disk_size

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  ip_allocation_policy {}
}

output "endpoint" {
  value = google_container_cluster.primary.endpoint
}

