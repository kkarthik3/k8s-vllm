# Runbook — vLLM on AWS EKS

All commands run in **Git Bash** from the repo root: `cd k8s-vllm/eks`

| Phase | When | Time |
|---|---|---|
| 0. Install tools | once per machine | 5 min |
| 1. AWS login | every session (SSO tokens expire) | 1 min |
| 2. Preflight + quota | once per account/region | 2 min (+ quota approval wait) |
| 3. Configure | once | 2 min |
| 4. Validate + plan | first time, and after any .tf change | 3 min |
| 5. Deploy | each session | ~30 min |
| 6. Use the API | while it is up | — |
| 7. Pause (optional) | short breaks | 3 min |
| 8. Destroy | **end of every session** | ~15 min |

---

## 0. Install tools (one time)

AWS CLI and kubectl are already on this machine. Install the rest from PowerShell, then **reopen Git Bash**:

```powershell
winget install Hashicorp.Terraform
winget install Helm.Helm
winget install jqlang.jq
```

Check:
```bash
terraform version && helm version && kubectl version --client && aws --version && jq --version
```

## 1. Log in to AWS (every session)

SSO (recommended):
```bash
aws configure sso          # first time only — creates a profile
aws sso login --profile <your-profile>
export AWS_PROFILE=<your-profile>
```
Or access keys: `aws configure` (never paste keys into chat or commit them).

Check — this identity becomes cluster admin:
```bash
aws sts get-caller-identity
```

## 2. Preflight (once per account/region)

```bash
REGION=us-east-1 bash scripts/preflight.sh
```
Need: all tools `ok`, **On-Demand G/VT quota ≥ 4**, at least 2 AZs listed.

If the quota is 0 or "TOO LOW", request it and **wait for approval** (minutes to ~1 day) before step 5:
```bash
aws service-quotas request-service-quota-increase --region us-east-1 --service-code ec2 --quota-code L-DB2E81BA --desired-value 4
```
Spot instead? Use quota code `L-3819A6DF` and set `gpu_capacity_type = "SPOT"` in step 3.

## 3. Configure (once)

```bash
cp terraform/example.tfvars terraform/terraform.tfvars
curl -s https://checkip.amazonaws.com
```
Edit `terraform/terraform.tfvars`:
- `region` — same as step 2
- `api_allowed_cidrs = ["<your-ip>/32"]` — the IP printed above (locks the EKS API to you)
- `gpu_capacity_type` — `ON_DEMAND` or `SPOT`

## 4. Validate and plan (first time, and after editing any .tf)

```bash
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```
Expect `Success! The configuration is valid.` and roughly 60–70 resources to add. Nothing is created yet.

## 5. Deploy

### Option A — one command
```bash
bash scripts/deploy.sh
```
Done when it prints `✅ Project verification complete.`

### Option B — step by step (same thing, with a check after each step)

| # | Command | Wait for |
|---|---|---|
| 5.1 | `terraform -chdir=terraform apply` (type `yes`) | `Apply complete!` (~15–20 min) |
| 5.2 | `aws eks update-kubeconfig --region us-east-1 --name vllm-serving-eks` | `Added new context` |
| 5.3 | `kubectl get nodes -L workload` | 2 nodes `Ready` (system + gpu) |
| 5.4 | `kubectl get pods -n gpu-operator` | all `Running` / `Completed` (~3–5 min) |
| 5.5 | `kubectl describe node -l workload=gpu \| grep nvidia.com/gpu` | `nvidia.com/gpu: 1` — **real checkpoint** |
| 5.6 | `kubectl apply -f k8s/vllm-deployment.yaml` | `deployment.apps/vllm created` |
| 5.7 | `kubectl get pods -l app=vllm -w` | `1/1 Running` (~8–10 min first boot; Ctrl+C to stop watching) |
| 5.8 | `kubectl logs -f deploy/vllm` | `Available KV cache memory` and `Application startup complete` |
| 5.9 | `bash scripts/verify.sh` | `✅ Project verification complete.` |

## 6. Use the API (while it is up)

Terminal 1 (leave it running):
```bash
kubectl port-forward svc/vllm 8000:8000
```
Terminal 2:
```bash
curl -s http://localhost:8000/v1/models | jq
```
```bash
curl -s http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"Qwen/Qwen2.5-7B-Instruct-AWQ","messages":[{"role":"user","content":"Explain Kubernetes in one sentence."}],"max_tokens":64}' | jq -r '.choices[0].message.content'
```
GPU usage:
```bash
kubectl exec deploy/vllm -- nvidia-smi
```

## 7. Pause for a short break (optional, < ~4 hrs)

```bash
bash scripts/gpu-nodes-scaling.sh in       # GPU off  (~$0.71/hr -> ~$0.19/hr)
bash scripts/gpu-nodes-scaling.sh out      # GPU back (~5–8 min to serving again)
bash scripts/verify.sh                     # after scaling out
```

## 8. Destroy (end of EVERY session)

```bash
bash scripts/destroy.sh
```
Done when both tables at the end are empty. If destroy errors (usually a timeout), just run it again.

Final sanity check (should print nothing):
```bash
aws ec2 describe-instances --region us-east-1 --filters "Name=tag:project,Values=vllm-serving-eks" "Name=instance-state-name,Values=running,pending" --query 'Reservations[].Instances[].InstanceId' --output text
```

---

## Next session

Steps **1 → 5 → 6 → 8** only (0, 2, 3, 4 are one-time).

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| apply fails: `InsufficientInstanceCapacity` / `VcpuLimitExceeded` | Quota not approved yet (step 2), or AZ out of g4dn — retry later or switch region |
| apply fails on `helm_release` with auth error | SSO expired: `aws sso login`, re-run apply |
| GPU node never `Ready` | `kubectl describe node -l workload=gpu`; node group events in EKS console |
| `nvidia.com/gpu` never shows `1` | `kubectl get pods -n gpu-operator`; `kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset` |
| vLLM pod `Pending` | Same as above — no GPU advertised yet; or `kubectl describe pod -l app=vllm` |
| vLLM `CrashLoopBackOff` / OOM | `kubectl logs deploy/vllm --previous`; lower `--gpu-memory-utilization` or `--max-model-len` |
| `ErrImagePull` / slow pull | Disk too small (`gpu_disk_size_gb`) or NAT issue; `kubectl describe pod -l app=vllm` |
| `kubectl` says Unauthorized | Wrong profile: `export AWS_PROFILE=...`, rerun step 5.2 |
| destroy hangs on VPC/subnet | A LoadBalancer Service/ELB was left: `kubectl get svc -A`, delete it, re-run destroy |
