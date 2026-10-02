#!/usr/bin/env bash
# Scale the GPU node group in / out without destroying the cluster.
#
# On EKS the trade-off is different from AKS: the control plane is NOT free ($0.10/hr), plus the
# system node (~$0.042/hr) and NAT gateway (~$0.045/hr). So:
#
#   scale to 0  ->  ~$0.19/hr  (~$4.5/day; ~5-8 min to first token on scale-out)
#   destroy     ->  $0.00/hr   (~20 min to rebuild)
#
#   stepping away < ~4 hrs   -> scale in
#   done for the day/longer  -> bash scripts/destroy.sh
#
# No Terraform drift: the GPU node group has min_size = 0 and the EKS module ignores
# desired_size after creation, so `terraform apply` will NOT scale it back out.
#
# Usage:
#   scripts/gpu-nodes-scaling.sh status | in | out
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform"
REGION="${REGION:-$(terraform -chdir="$TF" output -raw region 2>/dev/null || echo us-east-1)}"
CLUSTER="${CLUSTER:-$(terraform -chdir="$TF" output -raw cluster_name 2>/dev/null || echo vllm-serving-eks)}"
ACTION="${1:-status}"

run() { echo "\$ $*"; "$@"; }

# The EKS module names node groups "<key>-<random suffix>"; find the one starting with "gpu-".
NG=$(aws eks list-nodegroups --region "$REGION" --cluster-name "$CLUSTER" \
       --query "nodegroups[?starts_with(@, 'gpu')] | [0]" --output text)
[ -z "$NG" ] || [ "$NG" = "None" ] && { echo "FAIL: no gpu node group found in $CLUSTER"; exit 1; }

show() {
  echo; echo "==> Current state"
  run aws eks describe-nodegroup --region "$REGION" --cluster-name "$CLUSTER" --nodegroup-name "$NG" \
    --query 'nodegroup.{name:nodegroupName,status:status,scaling:scalingConfig,type:instanceTypes[0],capacity:capacityType}' \
    --output table
  run kubectl get nodes -l workload=gpu
}

case "$ACTION" in
  status) show ;;

  in|out)
    [ "$ACTION" = "in" ] && COUNT=0 || COUNT=1
    echo "==> Scaling node group '${NG}' to ${COUNT}"
    run aws eks update-nodegroup-config --region "$REGION" --cluster-name "$CLUSTER" \
      --nodegroup-name "$NG" --scaling-config "minSize=0,maxSize=1,desiredSize=${COUNT}" --output none || exit 1
    run aws eks wait nodegroup-active --region "$REGION" --cluster-name "$CLUSTER" --nodegroup-name "$NG"
    show
    if [ "$COUNT" -eq 0 ]; then
      echo; echo "GPU node released. Still billing ~\$0.19/hr (control plane + system node + NAT)."
      echo "Done for the day? bash scripts/destroy.sh (\$0)."
    else
      echo; echo "NOTE: the vllm pod must re-pull the ~11GB image and re-download weights"
      echo "      (no PVC yet) — budget ~5-8 min. Watch it with: bash scripts/verify.sh"
    fi
    ;;

  *) echo "Usage: $0 {status|in|out}"; exit 1 ;;
esac
