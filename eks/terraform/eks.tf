module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Public API endpoint so kubectl/helm work from your laptop. Restrict via api_allowed_cidrs.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.api_allowed_cidrs

  # Access entries (no aws-auth ConfigMap). Whoever runs `terraform apply` becomes cluster admin.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true # CNI must exist before nodes join, or they stay NotReady
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    # Required CPU pool — runs CoreDNS and the GPU Operator controllers, keeping cluster
    # overhead off the expensive card.
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.system_instance_type]

      min_size     = 1
      max_size     = 1
      desired_size = 1

      labels = {
        workload = "system"
      }
    }

    # GPU pool: 1x T4 serving the single vLLM pod.
    #
    # THE DRIVER DECISION (differs from AKS): the AL2023 NVIDIA AMI ships the NVIDIA driver and
    # container toolkit pre-installed, with containerd already configured for the nvidia runtime.
    # So the GPU Operator runs with driver.enabled=false / toolkit.enabled=false and only
    # provides the device plugin, GFD/NFD and DCGM exporter. Side benefits: much faster cold
    # start (no driver DaemonSet compile) and none of the AKS containerd drop-in version traps.
    gpu = {
      ami_type       = "AL2023_x86_64_NVIDIA"
      instance_types = [var.gpu_instance_type]
      capacity_type  = var.gpu_capacity_type

      # min 0 so scripts/gpu-nodes-scaling.sh can scale to zero. The module ignores
      # desired_size changes after creation, so scaling via CLI causes no Terraform drift.
      min_size     = 0
      max_size     = 1
      desired_size = 1

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.gpu_disk_size_gb
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }

      labels = {
        workload = "gpu"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "present"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}
