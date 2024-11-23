variable "cluster_name" {
  description = "Nome do cluster GKE"
  type        = string
}

variable "region" {
  description = "Região onde o cluster será criado"
  type        = string
}

variable "machine_type" {
  description = "Tipo de máquina para os nós"
  type        = string
  default     = "e2-medium"
}

variable "initial_nodes" {
  description = "Número inicial de nós no cluster"
  type        = number
  default     = 3
}
variable "disk_size" {
  description = "Tamanho do disco"
  type        = number
  default     = 100
}
