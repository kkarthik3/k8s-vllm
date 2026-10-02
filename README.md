# k8s-vllm

Production-shaped LLM serving with **vLLM** on managed Kubernetes. One NVIDIA T4 GPU, provisioned
with **Terraform**, made visible to Kubernetes by the **NVIDIA GPU Operator**, and serving
**Qwen2.5-7B-Instruct-AWQ** through vLLM's OpenAI-compatible API.

| Folder | Cloud | Cluster | GPU node | Start here |
|---|---|---|---|---|
| [`aks/`](aks/) | Azure | AKS | `Standard_NC4as_T4_v3` (T4) | [aks/README.md](aks/README.md) |
| [`eks/`](eks/) | AWS | EKS | `g4dn.xlarge` (T4) | [eks/README.md](eks/README.md) · [eks/RUNBOOK.md](eks/RUNBOOK.md) |

Both clouds use the same GPU, so the vLLM manifest and engine flags are the same in both. The
differences are in the infrastructure: networking, how the GPU driver is installed, cluster auth,
and cost. The table in [eks/README.md](eks/README.md#azure--aws-mapping) maps each one.

## Credits

The `aks/` project is copied from **[shiqs90/vllm-serving-aks](https://github.com/shiqs90/vllm-serving-aks)**,
including its README, docs, architecture diagram and video walkthrough. All credit for it goes to the
original author. `eks/` is an AWS port derived from it.

## Teardown

Both projects bill by the hour while a GPU node is up. Always tear down when you're done:
`terraform destroy` for AKS, `bash eks/scripts/destroy.sh` for EKS.
