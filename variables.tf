variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "case6"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "eks_cluster_name" {
  description = "Existing EKS cluster name in us-east-1"
  type        = string
  default     = "case8-eks"
}

variable "k8s_namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "default"
}

variable "deployment_name" {
  description = "Kubernetes Deployment metadata.name"
  type        = string
  default     = "webapp"
}
