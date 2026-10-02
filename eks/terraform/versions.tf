terraform {
  required_version = ">= 1.10"

  # State backend: local by default. For team use, uncomment backend.tf (S3 + native lockfile).
  # (The AKS original used an HCP Terraform workspace in Local execution mode — that also works
  # here unchanged if you prefer it; just add the same `cloud {}` block.)

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # terraform-aws-modules/eks v20.x supports AWS provider 5.x only.
      version = "~> 5.95"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}
