# Optional remote state. Create the bucket once (versioning on), then uncomment and run
# `terraform init -migrate-state`. `use_lockfile` (Terraform >= 1.10) replaces the DynamoDB lock table.
#
# terraform {
#   backend "s3" {
#     bucket       = "<your-tfstate-bucket>"
#     key          = "vllm-serving-eks/terraform.tfstate"
#     region       = "us-east-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
