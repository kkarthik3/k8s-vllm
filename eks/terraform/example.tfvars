# cp example.tfvars terraform.tfvars  (terraform.tfvars is gitignored)
region               = "us-east-1"
cluster_name         = "vllm-serving-eks"
# kubernetes_version = "1.33"
api_allowed_cidrs    = ["0.0.0.0/0"] # tighten to your egress IP, e.g. ["203.0.113.10/32"]
system_instance_type = "t3.medium"
gpu_instance_type    = "g4dn.xlarge"
gpu_capacity_type    = "ON_DEMAND" # or "SPOT" (~65-70% cheaper, needs Spot G/VT quota)
gpu_disk_size_gb     = 100
