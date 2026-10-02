# vLLM Serving on AWS EKS
(Terraform + NVIDIA GPU Operator + T4) — AWS port of [shiqs90/vllm-serving-aks](https://github.com/shiqs90/vllm-serving-aks)

Provision a GPU node on **EKS with Terraform**, run the **NVIDIA GPU Operator**, and serve
**Qwen2.5-7B-Instruct-AWQ** on vLLM's OpenAI-compatible API (`/v1/completions`).

## Azure → AWS mapping

| Concern | AKS original | EKS port |
|---|---|---|
| Network | Implicit VNet in `MC_*` RG | `vpc.tf`: own VPC, 2 private + 2 public subnets, 1 NAT GW |
| Cluster | `azurerm_kubernetes_cluster` (Free tier) | `terraform-aws-modules/eks` v20 ($0.10/hr control plane) |
| System pool | `Standard_D2s_v3` | `t3.medium` managed node group |
| GPU pool | `Standard_NC4as_T4_v3` (T4) | `g4dn.xlarge` (same T4, 16 GiB host RAM) |
| GPU OS | Ubuntu 22.04, `gpu_driver = "None"` | `AL2023_x86_64_NVIDIA` AMI (driver + toolkit baked in) |
| GPU Operator | `driver.enabled=true`, containerd path hack | `driver.enabled=false`, `toolkit.enabled=false` |
| Taint / label | `nvidia.com/gpu=present:NoSchedule`, `workload=gpu` | identical |
| k8s auth for Helm | AKS admin client cert | `aws eks get-token` exec plugin |
| Cluster access | AKS local admin | EKS access entries; creator = cluster admin |
| State | HCP Terraform (local exec) | local by default; S3 + lockfile in `backend.tf` |
| Quota | `NCASv3_T4` vCPU | EC2 `Running On-Demand G and VT instances` (L-DB2E81BA) ≥ 4 |

The vLLM manifest and engine flags stay the same because it's the same GPU (T4, SM 7.5, 15 GiB).
The AZs are picked automatically from those that actually offer `g4dn.xlarge`. The GPU root disk is
set to 100 GB because the 20 GB EKS default can't hold the image plus weights.

## Layout

```
terraform/  versions.tf providers.tf variables.tf vpc.tf eks.tf gpu-operator.tf outputs.tf backend.tf example.tfvars
k8s/        vllm-deployment.yaml      # Deployment + ClusterIP Service
scripts/    preflight.sh deploy.sh verify.sh gpu-nodes-scaling.sh destroy.sh
```

## Run it

Prereqs: AWS CLI v2 (logged in), Terraform ≥ 1.10, kubectl, helm, jq. On Windows, use Git Bash.

```bash
bash scripts/preflight.sh                 # quota, AZs, spot price
cp terraform/example.tfvars terraform/terraform.tfvars   # optional overrides
bash scripts/deploy.sh                    # apply -> kubeconfig -> wait for GPU -> vLLM -> verify
bash scripts/destroy.sh                   # ALWAYS when done
```

`deploy.sh` ends when `verify.sh` prints `✅ Project verification complete.`

## Cost (us-east-1, on-demand, approximate)

| Component | $/hr |
|---|---|
| g4dn.xlarge (T4) | 0.526 |
| t3.medium system node | 0.042 |
| EKS control plane | 0.100 |
| NAT gateway (+ $0.045/GB processed, ~17 GB first boot) | 0.045 |
| **Total** | **~0.71** |

With the GPU scaled to 0 (`gpu-nodes-scaling.sh in`) it's about $0.19/hr. Destroyed, it's $0.
`gpu_capacity_type = "SPOT"` brings the GPU down to roughly $0.16–0.20/hr, but it needs Spot G/VT quota (L-3819A6DF).
EKS control plane time isn't free, so **destroy by default** and set an AWS Budgets alert.
