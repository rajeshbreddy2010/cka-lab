#!/usr/bin/env bash
set -euo pipefail

NS=relative-fawn
FILLER_NS=lab-filler
LABEL_KEY=lab-relative-fawn   # unique key so other labs' cleanup can't remove it

# Design target: after the capacity-reserver (below) takes the rest of the node,
# this much CPU/memory is left free for the 3 WordPress Pods.
#   fair share = free / 3 = ~113m / ~226Mi  ->  100m / 200Mi with a ~10% margin
FREE_CPU_TARGET=340   # millicores
FREE_MEM_TARGET=680   # Mi

# Default: first node that is NOT tainted NoSchedule (skips the control plane)
NODE=${1:-$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[*].effect}{"\n"}{end}' \
  | awk '!/NoSchedule/ {print $1; exit}')}
[[ -n "$NODE" ]] || { echo "No schedulable node found; pass one: bash setup.sh <node>"; exit 1; }

# --- clean any previous run (so free capacity is measured without it) ---
kubectl delete namespace "$NS" "$FILLER_NS" --ignore-not-found --wait=true

# --- helpers: sum CPU (millicores) and memory (Mi) from kubectl output ---
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

# --- free capacity on the node right now ---
ALLOC_CPU=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.cpu}' | to_m)
ALLOC_MEM=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.memory}' | to_mi)

SEL="spec.nodeName=$NODE,status.phase!=Succeeded,status.phase!=Failed"
USED_CPU=$(kubectl get pods -A --field-selector "$SEL" \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.cpu}{"\n"}{end}{end}' | to_m)
USED_MEM=$(kubectl get pods -A --field-selector "$SEL" \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.memory}{"\n"}{end}{end}' | to_mi)

FREE_CPU=$((ALLOC_CPU - USED_CPU))
FREE_MEM=$((ALLOC_MEM - USED_MEM))
echo "Node $NODE: allocatable ${ALLOC_CPU}m / ${ALLOC_MEM}Mi, in use ${USED_CPU}m / ${USED_MEM}Mi, free ${FREE_CPU}m / ${FREE_MEM}Mi"

if (( FREE_CPU < FREE_CPU_TARGET + 20 || FREE_MEM < FREE_MEM_TARGET + 20 )); then
  echo "Node $NODE has too little free capacity (need at least $((FREE_CPU_TARGET + 20))m / $((FREE_MEM_TARGET + 20))Mi free)."
  echo "Free up the node or pass a bigger one: bash setup.sh <node>"
  exit 1
fi

# The capacity-reserver takes everything except the target, leaving exactly
# ~340m / ~680Mi for the WordPress Pods.
FILL_CPU=$((FREE_CPU - FREE_CPU_TARGET))
FILL_MEM=$((FREE_MEM - FREE_MEM_TARGET))

# Requests deliberately set to 60% of what is left for the app -> only 1 Pod fits
BAD_CPU="$((FREE_CPU_TARGET * 60 / 100))m"
BAD_MEM="$((FREE_MEM_TARGET * 60 / 100))Mi"

echo "capacity-reserver will request ${FILL_CPU}m / ${FILL_MEM}Mi"
echo "Broken WordPress requests per Pod: $BAD_CPU CPU, $BAD_MEM memory"

# Clear this label from every node first, then set it fresh on $NODE only
kubectl label nodes --all "$LABEL_KEY"- --overwrite 2>/dev/null || true
kubectl label node "$NODE" "$LABEL_KEY"=true --overwrite
kubectl create namespace "$NS"
kubectl create namespace "$FILLER_NS"

# --- capacity-reserver: holds the rest of the node so the free amount is known ---
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capacity-reserver
  namespace: $FILLER_NS
  labels:
    app: capacity-reserver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: capacity-reserver
  template:
    metadata:
      labels:
        app: capacity-reserver
    spec:
      nodeSelector:
        $LABEL_KEY: "true"
      containers:
      - name: reserver
        image: busybox:stable
        command: ["sleep", "infinity"]
        resources:
          requests:
            cpu: "${FILL_CPU}m"
            memory: "${FILL_MEM}Mi"
EOF

kubectl rollout status deploy/capacity-reserver -n "$FILLER_NS" --timeout=90s || {
  echo "capacity-reserver could not be scheduled (the node had less free capacity than measured)."
  echo "Re-run on a quieter node, or lower FREE_CPU_TARGET / FREE_MEM_TARGET."
  exit 1
}

# --- the WordPress application ---
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
echo "Done. About ${FREE_CPU_TARGET}m CPU / ${FREE_MEM_TARGET}Mi memory is free for the app on node $NODE."
echo "Expect 1 Pod Running and 2 Pending:"
echo "  kubectl get pods -n $NS -o wide"
echo "Confirm the label landed on the right node with:"
echo "  kubectl get nodes -l $LABEL_KEY=true"
