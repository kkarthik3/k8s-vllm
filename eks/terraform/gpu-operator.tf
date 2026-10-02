resource "helm_release" "gpu_operator" {
  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = var.gpu_operator_version
  namespace        = "gpu-operator"
  create_namespace = true

  # The AL2023 NVIDIA AMI already has the driver and the nvidia container toolkit, so the
  # Operator must NOT install its own (two drivers / two runtime configs = broken node).
  set {
    name  = "driver.enabled"
    value = "false"
  }
  set {
    name  = "toolkit.enabled"
    value = "false"
  }

  # Tolerate the custom GPU taint so the Operator's DaemonSets land on the GPU node.
  set {
    name  = "daemonsets.tolerations[0].key"
    value = "nvidia.com/gpu"
  }
  set {
    name  = "daemonsets.tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "daemonsets.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Node groups + CoreDNS must be up first, or the Operator's webhooks/controllers have nowhere to run.
  depends_on = [module.eks]
}
