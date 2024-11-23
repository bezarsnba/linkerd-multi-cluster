variable "project_id" {
  description = "ID do projeto no GCP"
  type        = string
}

variable "default_region" {
  description = "Região padrão para o provider"
  type        = string
  default     = "us-central1"
}

variable "cluster_1_name" {
  description = "Nome do primeiro cluster"
  type        = string
  default     = "cluster-1"
}

variable "cluster_1_region" {
  description = "Região do primeiro cluster"
  type        = string
  default     = "us-central1"
}

variable "cluster_2_name" {
  description = "Nome do segundo cluster"
  type        = string
  default     = "cluster-2"
}

variable "cluster_2_region" {
  description = "Região do segundo cluster"
  type        = string
  default     = "europe-west1"
}

variable "machine_type" {
  description = "Tipo de máquina para os nós"
  type        = string
  default     = "e2-medium"
}

variable "initial_nodes" {
  description = "Número inicial de nós por cluster"
  type        = number
  default     = 2
}

