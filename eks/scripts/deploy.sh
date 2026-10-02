#!/usr/bin/env bash
# End-to-end bring-up: terraform apply -> kubeconfig -> wait for nvidia.com/gpu -> vLLM -> verify.
# Run from the repo root or anywhere; paths are resolved relative to this script.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform"

run() { echo "\$ $*"; "$@"; }

echo "==> [1/5] terraform init + apply (~15-20 min: VPC, EKS control plane, 2 node groups, GPU Operator)"
run terraform -chdir="$TF" init -upgrade
run terraform -chdir="$TF" apply -auto-approve "$@"

REGION=$(terraform -chdir="$TF" output -raw region)
CLUSTER=$(terraform -chdir="$TF" output -raw cluster_name)

echo; echo "==> [2/5] Point kubectl at the cluster"
run aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"
run kubectl get nodes -L workload -o wide

echo; echo "==> [3/5] Waiting for the GPU to be advertised (nvidia.com/gpu = 1) — the real checkpoint"
for i in $(seq 1 60); do
  GPUS=$(kubectl get nodes -l workload=gpu -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)
  [ "${GPUS:-}" = "1" ] && { echo "    nvidia.com/gpu: 1  ✔"; break; }
  [ "$i" = "60" ] && { echo "FAIL: GPU never advertised. Check: kubectl get pods -n gpu-operator"; exit 1; }
  echo "    not yet (${GPUS:-none}) — retry $i/60"; sleep 10
done

echo; echo "==> [4/5] Deploy vLLM"
run kubectl apply -f "$ROOT/k8s/vllm-deployment.yaml"

echo; echo "==> [5/5] Verify"
bash "$ROOT/scripts/verify.sh"
