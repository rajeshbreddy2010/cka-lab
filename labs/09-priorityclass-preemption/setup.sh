#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NS=priority
# Default: first node that is NOT tainted NoSchedule (skips the control plane)
NODE=${1:-$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[*].effect}{"\n"}{end}' \
  | awk '!/NoSchedule/ {print $1; exit}')}
[[ -n "$NODE" ]] || { echo "No schedulable node found; pass one: bash setup.sh <node>"; exit 1; }

# ---------- clean previous runs ----------
kubectl delete namespace $NS --ignore-not-found --wait=true
kubectl delete priorityclass high-priority batch-low standard-user business-critical --ignore-not-found

# ---------- helpers: sum CPU (millicores) and memory (Mi) ----------
to_m() {
  awk '{ if ($0 ~ /m$/) { sub(/m$/, ""); s += $0 } else if ($0 != "") s += $0 * 1000 } END { printf "%d", s }'
}
to_mi() {
  awk '
    function conv(v) {
      if (v ~ /Ki$/) { sub(/Ki$/, "", v); return v / 1024 }
      if (v ~ /Mi$/) { sub(/Mi$/, "", v); return v }
      if (v ~ /Gi$/) { sub(/Gi$/, "", v); return v * 1024 }
      if (v ~ /k$/)  { sub(/k$/,  "", v); return v * 1000 / 1048576 }
      if (v ~ /M$/)  { sub(/M$/,  "", v); return v * 1000000 / 1048576 }
      if (v ~ /G$/)  { sub(/G$/,  "", v); return v * 1000000000 / 1048576 }
      return v / 1048576
    }
    NF { s += conv($1) } END { printf "%d", s }'
}

# ---------- work out free capacity on the node ----------
ALLOC_CPU=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.cpu}' | to_m)
ALLOC_MEM=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.memory}' | to_mi)

SEL="spec.nodeName=$NODE,status.phase!=Succeeded,status.phase!=Failed"
USED_CPU=$(kubectl get pods -A --field-selector "$SEL" \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.cpu}{"\n"}{end}{end}' | to_m)
USED_MEM=$(kubectl get pods -A --field-selector "$SEL" \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.memory}{"\n"}{end}{end}' | to_mi)

FREE_CPU=$((ALLOC_CPU - USED_CPU))
FREE_MEM=$((ALLOC_MEM - USED_MEM))
echo "Node $NODE: free ${FREE_CPU}m CPU, ${FREE_MEM}Mi memory"
[[ $FREE_CPU -gt 100 && $FREE_MEM -gt 200 ]] || { echo "Not enough free capacity on the node"; exit 1; }

OTHER_CPU="$((FREE_CPU * 14 / 100))m"; OTHER_MEM="$((FREE_MEM * 14 / 100))Mi"   # 4 pods -> 56%
LOG_CPU="$((FREE_CPU * 20 / 100))m";   LOG_MEM="$((FREE_MEM * 20 / 100))Mi"     # 3 pods -> 60%

# ---------- namespace, node label, priority classes ----------
kubectl label node "$NODE" lab=priority --overwrite
kubectl create namespace $NS

cat <<EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: batch-low
value: 1000
description: "Low priority batch work"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: standard-user
value: 50000
description: "Standard user workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: business-critical
value: 250000
description: "Highest user-defined priority class"
EOF

# ---------- "other" deployments (no priorityClassName -> priority 0) ----------
for APP in web-frontend batch-worker; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $APP
  template:
    metadata:
      labels:
        app: $APP
    spec:
      nodeSelector:
        lab: priority
      containers:
      - name: main
        image: busybox:stable
        command: ["/bin/sh", "-c", "while true; do sleep 30; done"]
        resources:
          requests:
            cpu: "$OTHER_CPU"
            memory: "$OTHER_MEM"
EOF
done

kubectl rollout status deploy/web-frontend -n $NS --timeout=120s
kubectl rollout status deploy/batch-worker -n $NS --timeout=120s

# ---------- busybox-logger (needs more room than is left) ----------
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox-logger
  namespace: $NS
spec:
  replicas: 3
  selector:
    matchLabels:
      app: busybox-logger
  template:
    metadata:
      labels:
        app: busybox-logger
    spec:
      nodeSelector:
        lab: priority
      containers:
      - name: logger
        image: busybox:stable
        command: ["/bin/sh", "-c", "while true; do echo logging; sleep 5; done"]
        resources:
          requests:
            cpu: "$LOG_CPU"
            memory: "$LOG_MEM"
EOF

echo
echo "Done. Expect busybox-logger with 2/3 Pods running and 1 Pending:"
echo "  kubectl get pods -n $NS"
echo "  kubectl get priorityclass"
