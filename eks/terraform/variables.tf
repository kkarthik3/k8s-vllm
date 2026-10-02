variable "region" {
  description = "AWS region. Must have 'Running On-Demand G and VT instances' quota >= 4 vCPU (or the Spot equivalent)."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name (also used for the VPC name and the `project` tag)."
  type        = string
  default     = "vllm-serving-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version, e.g. \"1.33\". null = EKS default (run `aws eks describe-cluster-versions` to list)."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR. Private /20 per AZ for nodes + pods (VPC CNI gives pods VPC IPs), public /24 per AZ for NAT/LBs."
  type        = string
  default     = "10.0.0.0/16"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Tighten to your office/VPN egress IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_instance_type" {
  description = "CPU system node group (CoreDNS, GPU Operator controllers). Equivalent of AKS Standard_D2s_v3."
  type        = string
  default     = "t3.medium"
}

variable "gpu_instance_type" {
  description = "GPU node instance type. g4dn.xlarge = 1x NVIDIA T4 16GB, 4 vCPU, 16 GiB — same GPU as AKS Standard_NC4as_T4_v3, so the vLLM flags carry over unchanged."
  type        = string
  default     = "g4dn.xlarge"
}

variable "gpu_capacity_type" {
  description = "ON_DEMAND or SPOT. Spot is ~65-70% cheaper but can be reclaimed with a 2-minute warning."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.gpu_capacity_type)
    error_message = "gpu_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "gpu_disk_size_gb" {
  description = "GPU node root volume. The ~11GB vLLM image + ~5.5GB weights do not fit the 20GB EKS default."
  type        = number
  default     = 100
}

variable "gpu_operator_version" {
  description = "NVIDIA GPU Operator Helm chart version."
  type        = string
  default     = "v26.3.2"
}
