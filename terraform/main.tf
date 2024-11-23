provider "google" {
  project = var.project_id
  region  = var.default_region
}

module "cluster_1" {
  source        = "./modules/gke"
  cluster_name  = var.cluster_1_name
  region        = var.cluster_1_region
  machine_type  = var.machine_type
  initial_nodes = var.initial_nodes
}

module "cluster_2" {
  source        = "./modules/gke"
  cluster_name  = var.cluster_2_name
  region        = var.cluster_2_region
  machine_type  = var.machine_type
  initial_nodes = var.initial_nodes
}

output "cluster_1_endpoint" {
  value = module.cluster_1.endpoint
}

output "cluster_2_endpoint" {
  value = module.cluster_2.endpoint
}

