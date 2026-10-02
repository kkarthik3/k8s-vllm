#!/usr/bin/env bash
# Pre-flight: identity, GPU quota, AZ availability, Spot price. Run before the first apply.
# Every command is printed (as "$ ...") right before it runs.
set -uo pipefail

REGION="${REGION:-us-east-1}"
GPU_TYPE="${GPU_TYPE:-g4dn.xlarge}"
NEED_VCPU=4   # g4dn.xlarge = 4 vCPU

run() { echo "\$ $*"; "$@"; }

echo "==> [1/5] Tools"
for t in aws terraform kubectl helm jq; do
  command -v "$t" >/dev/null && echo "  ok   $t" || echo "  MISSING $t"
done

echo; echo "==> [2/5] Who am I (terraform will make this principal cluster admin)"
run aws sts get-caller-identity --output table || { echo "FAIL: not logged in (aws sso login / aws configure)"; exit 1; }

echo; echo "==> [3/5] GPU vCPU quota in ${REGION} (need >= ${NEED_VCPU})"
# L-DB2E81BA = Running On-Demand G and VT instances; L-3819A6DF = All G and VT Spot Instance Requests
for q in L-DB2E81BA:On-Demand L-3819A6DF:Spot; do
  code="${q%%:*}"; label="${q##*:}"
  val=$(aws service-quotas get-service-quota --region "$REGION" --service-code ec2 --quota-code "$code" \
          --query 'Quota.Value' --output text 2>/dev/null || echo "?")
  status="OK"; [ "$val" = "?" ] && status="UNKNOWN"
  [ "$val" != "?" ] && awk "BEGIN{exit !($val < $NEED_VCPU)}" && status="TOO LOW"
  printf "  %-10s G/VT vCPU quota: %-6s %s\n" "$label" "$val" "$status"
done
echo "  Raise with: aws service-quotas request-service-quota-increase --region $REGION \\"
echo "                --service-code ec2 --quota-code L-DB2E81BA --desired-value 4"

echo; echo "==> [4/5] AZs offering ${GPU_TYPE} (terraform picks the first 2)"
run aws ec2 describe-instance-type-offerings --region "$REGION" --location-type availability-zone \
  --filters "Name=instance-type,Values=${GPU_TYPE}" --query 'InstanceTypeOfferings[].Location' --output text

echo; echo "==> [5/5] Current Spot price for ${GPU_TYPE} (on-demand us-east-1 is ~\$0.526/hr)"
run aws ec2 describe-spot-price-history --region "$REGION" --instance-types "$GPU_TYPE" \
  --product-descriptions "Linux/UNIX" --start-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'SpotPriceHistory[].[AvailabilityZone,SpotPrice]' --output table

echo; echo "Pre-flight done. Next: bash scripts/deploy.sh"
