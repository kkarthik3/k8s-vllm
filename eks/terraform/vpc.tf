# Unlike AKS (which builds its VNet in a hidden MC_* resource group), EKS needs a VPC you own.
# The upside: the network is in state, in the diff, and in the cost reasoning.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Not every AZ offers every GPU type (e.g. us-east-1e has no g4dn). Pick AZs that do, so the
# GPU node group never lands in a subnet where the instance can't launch.
data "aws_ec2_instance_type_offerings" "gpu" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.gpu_instance_type]
  }
}

locals {
  # EKS requires subnets in at least 2 AZs.
  azs = slice(sort(tolist(setintersection(
    data.aws_availability_zones.available.names,
    data.aws_ec2_instance_type_offerings.gpu.locations,
  ))), 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = var.cluster_name
  cidr = var.vpc_cidr
  azs  = local.azs

  # 10.0.0.0/20, 10.0.16.0/20 — nodes and pods
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  # 10.0.48.0/24, 10.0.49.0/24 — NAT gateway, future load balancers
  public_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  # One NAT gateway (~$0.045/hr + data) instead of one per AZ: fine for a single-GPU demo.
  # Nodes pull the ~11GB image and weights through it.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Lets the AWS Load Balancer Controller / in-tree LB find subnets later (Service type=LoadBalancer).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
