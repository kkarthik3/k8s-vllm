#!/usr/bin/env bash
# Teardown. Deletes in-cluster objects Terraform doesn't own (anything that could create an ELB
# or EBS volume), then terraform destroy, then checks nothing GPU-shaped is still billing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform"

run() { echo "\$ $*"; "$@"; }

REGION=$(terraform -chdir="$TF" output -raw region 2>/dev/null || echo "${REGION:-us-east-1}")
CLUSTER=$(terraform -chdir="$TF" output -raw cluster_name 2>/dev/null || echo "${CLUSTER:-vllm-serving-eks}")

echo "==> [1/3] Remove vLLM (a LoadBalancer Service left behind would orphan an ELB and block VPC delete)"
run kubectl delete -f "$ROOT/k8s/vllm-deployment.yaml" --ignore-not-found --wait=true || true
LBS=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
if [ -n "$LBS" ]; then
  echo "    Deleting remaining LoadBalancer services:"; echo "$LBS"
  echo "$LBS" | while IFS=/ read -r ns name; do kubectl delete svc -n "$ns" "$name" --wait=true; done
fi

echo; echo "==> [2/3] terraform destroy (~10-15 min)"
run terraform -chdir="$TF" destroy -auto-approve || { echo "FAIL: destroy errored — re-run this script."; exit 1; }

echo; echo "==> [3/3] Confirm nothing tagged project=${CLUSTER} is still running"
run aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:project,Values=${CLUSTER}" "Name=instance-state-name,Values=pending,running,stopping" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output table
run aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=tag:project,Values=${CLUSTER}" "Name=state,Values=available,pending" \
  --query 'NatGateways[].NatGatewayId' --output text

echo; echo "✅ Teardown complete (empty tables above = \$0/hr)."
