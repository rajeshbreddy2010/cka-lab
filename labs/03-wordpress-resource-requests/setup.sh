#!/usr/bin/env bash
set -euo pipefail

NS=relative-fawn
LABEL_KEY=lab-relative-fawn   # unique key so other labs' cleanup can't remove it

# Default: first node that is NOT tainted NoSchedule (skips the control plane)
NODE=${1:-$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[*].effect}{"\n"}{end}' \
  | awk '!/NoSchedule/ {print $1; exit}')}
[[ -n "$NODE" ]] || { echo "No schedulable node found; pass one: bash setup.sh <node>"; exit 1; }

# --- read node allocatable and convert to millicores / Mi ---
cpu=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.cpu}')
mem=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.memory}')

if [[ $cpu == *m ]]; then cpu_m=${cpu%m}; else cpu_m=$((cpu * 1000)); fi

case $mem in
  *Ki) mem_mi=$(( ${mem%Ki} / 1024 )) ;;
  *Mi) mem_mi=${mem%Mi} ;;
  *Gi) mem_mi=$(( ${mem%Gi} * 1024 )) ;;
  *)   mem_mi=$(( mem / 1024 / 1024 )) ;;
esac

# Requests deliberately set to 60% of the node -> only 1 Pod can be scheduled
BAD_CPU="$((cpu_m * 60 / 100))m"
BAD_MEM="$((mem_mi * 60 / 100))Mi"

echo "Node: $NODE  allocatable: ${cpu_m}m CPU, ${mem_mi}Mi memory"
echo "Broken requests per Pod: $BAD_CPU CPU, $BAD_MEM memory"

# Clear this label from every node first, then set it fresh on $NODE only
kubectl label nodes --all "$LABEL_KEY"- --overwrite 2>/dev/null || true
kubectl label node "$NODE" "$LABEL_KEY"=true --overwrite
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: $NS
  labels:
    app: wordpress
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      nodeSelector:
        $LABEL_KEY: "true"
      containers:
      - name: wordpress
        image: wordpress:6-apache
        ports:
        - containerPort: 80
        env:
        - name: WORDPRESS_DB_HOST
          value: "mysql.$NS.svc"
        resources:
          requests:
            cpu: "$BAD_CPU"
            memory: "$BAD_MEM"
      initContainers:
      - name: init-setup
        image: busybox:stable
        imagePullPolicy: IfNotPresent
        command:
        - /bin/sh
        - -c
        args:
        - echo init done; sleep 1
        resources:
          requests:
            memory: "500Mi"
            cpu: "250m"
          limits:
            memory: "1000Mi"
            cpu: "500m"
EOF

echo
echo "Done. Expect 1 Pod Running and 2 Pending on node $NODE:"
echo "  kubectl get pods -n $NS -o wide"
echo "Confirm the label landed on the right node with:"
echo "  kubectl get nodes -l $LABEL_KEY=true"
