provider "aws" {
  region = var.region
  # Credentials come from the local AWS CLI profile / SSO session (or AWS_* env vars).

  # Tag everything so Cost Explorer can attribute spend (equivalent of the AKS `project` tag).
  default_tags {
    tags = {
      project = var.cluster_name
    }
  }
}

# EKS exports no static admin certificate (unlike AKS kube_config), so helm authenticates
# with a short-lived token from `aws eks get-token`. Requires the AWS CLI on PATH.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
