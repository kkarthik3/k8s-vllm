# Project Summary — `vllm-serving-aks`

vLLM serving foundation on Azure AKS with a T4.

Built **2026-08-06**. Verified: `/v1/completions` returns tokens from a Terraform-provisioned
GPU node.

---

## War stories

### 1. Spot was blocked by a quota nobody checks

GPU quota is the first gate on a new subscription — human-reviewed, no guaranteed turnaround.
`NCASv3_T4` came back at **4 vCPUs**. But Spot, at **$0.198/hr vs $0.684/hr on-demand** (71% off
the component that is ~84% of the bill), was still unusable:

```
Standard NCASv3_T4 Family vCPUs        0/4    <- GPU quota, approved
Total Regional Low-priority vCPUs      0/3    <- the actual blocker
```

The VM needs 4 low-priority vCPUs; the subscription allows 3. **Spot and on-demand draw from
separate quota pools** — enumerate every family before designing for cost, not just the obvious one.

---

### 2. A Service name crashes vLLM on boot — `CrashLoopBackOff` (FIXED)

**Symptom.** Pod schedules, starts, dies immediately: `VLLM_PORT ... appears to be a URI`.

**Cause.** `enableServiceLinks` defaults to **`true`**, so the kubelet injects Docker-link env
vars for every Service in the namespace. A Service named `vllm` produces
`VLLM_PORT=tcp://10.0.x.x:8000`; vLLM reads that as its own listen port, gets a URI, and exits.
Slow to diagnose because the error names a variable **you never set** — it isn't in the manifest.

**Fix.** `enableServiceLinks: false` in the pod spec
([`k8s/vllm-deployment.yaml`](../k8s/vllm-deployment.yaml)). Already applied here, so vLLM came
up clean on the first apply. `kubectl exec <pod> -- env | grep <APP>` settles it in seconds.

---

### 3. containerd config-version mismatch → GPU node `NotReady`

**Symptom.** GPU node comes up, GPU Operator reports success, node goes `NotReady`:
`drop-in config version 4 higher than root config version 2`.

**Cause.** AKS's default Ubuntu 24.04 image ships **containerd 2.3** (root config version 2).
The GPU Operator toolkit writes its NVIDIA runtime as a drop-in at a higher version; containerd
2.x validates it and refuses to start. No runtime → no kubelet → `NotReady`. Nothing in the
Operator's own logs points at it.

**Fix — both layers:**

| Layer | Setting | File |
|---|---|---|
| Pin the OS image | `os_sku = "Ubuntu2204"` (containerd 1.7, no version check) | [`terraform/aks.tf`](../terraform/aks.tf) |
| Redirect the toolkit | `CONTAINERD_CONFIG=/etc/containerd/config.toml` | [`terraform/gpu-operator.tf`](../terraform/gpu-operator.tf) |

**The command that tells you instantly:**

```
$ kubectl get nodes -o wide

NAME                             STATUS   OS-IMAGE             CONTAINER-RUNTIME
aks-gpu-13478662-vmss000000      Ready    Ubuntu 22.04.5 LTS   containerd://1.7.33-1
aks-system-33479023-vmss000000   Ready    Ubuntu 24.04.4 LTS   containerd://2.3.2-2
```

Read the **`CONTAINER-RUNTIME`** column. This is healthy: only the GPU pool is pinned to 1.7,
because only it runs the GPU toolkit. When the bug hits, that column reads
**`containerd://unknown`** with `STATUS NotReady` — containerd never started, so the node can't
report its runtime version.

**Takeaway:** "use the latest node image" isn't a strategy for GPU nodes — the accelerator stack
(driver → toolkit → device plugin) has a compatibility matrix that lags the base OS.

---

## Future enhancements

- **Raise `--max-num-seqs`.** vLLM reports headroom for **33.46x** concurrency at 4096 tokens;
  the config caps it at 8. Raise and re-measure under load.
- **Load testing.** No throughput or latency numbers captured yet.
- **External access.** `port-forward` only today — no Ingress, no TLS.
- **Model weight caching.** Weights re-download on every pod restart; back the HF cache with a PV.
- **Raise low-priority quota → move to Spot.** ~60% off the total bill, at the cost of handling
  eviction (2-minute warning, graceful drain, interrupted in-flight requests).
