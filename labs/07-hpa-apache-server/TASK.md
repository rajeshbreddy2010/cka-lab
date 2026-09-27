# Lab: HorizontalPodAutoscaler for `apache-server` (namespace `autoscale`)

## Scenario
The `apache-server` Deployment in the `autoscale` namespace needs to scale
automatically based on CPU usage.

## Task
Create a new HorizontalPodAutoscaler (HPA) named `apache-server` in the
`autoscale` namespace. This HPA must target the existing Deployment called
`apache-server` in the `autoscale` namespace.

Set the HPA to aim for **50% CPU usage per Pod**. Configure it to have **at
least 1 Pod and no more than 4 Pods**. Also, set the **downscale
stabilization window to 30 seconds**.

---

## 0. Prerequisite: metrics-server

An HPA needs CPU/memory metrics from the **Metrics API**, which
`metrics-server` provides. Without it, the HPA object can be created but
will show `<unknown>` for `TARGETS` forever and never actually scale.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# On kind/minikube/self-signed kubelet certs, metrics-server needs this flag,
# otherwise it can't scrape kubelets:
kubectl patch deployment metrics-server -n kube-system --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}
]'

kubectl rollout status deploy/metrics-server -n kube-system --timeout=90s
kubectl top nodes   # should return numbers, not an error, once it's ready (can take ~1 min)
```

---
