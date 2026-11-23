# Lab: Fix WordPress Pods stuck in Pending (namespace `relative-fawn`)

## Scenario
You manage a WordPress application. Some Pods are not starting because their
resource requests are too high.

## Task
The WordPress application in the `relative-fawn` namespace consists of a
`wordpress` Deployment with **3 replicas**.

Adjust **all Pod resource requests** as follows:

- Divide the node's resources evenly across all 3 Pods.
- Give each Pod a fair share of CPU and memory.
- Use the same requests for the init container (`init-setup`) and the main
  container (`wordpress`).
- A request can never exceed its limit. `init-setup` has limits of 500m CPU /
  1000Mi memory; if your new request is higher, raise the limit to match.
- Leave a small safety margin (about 10-15%) so the node is not 100% committed.

You may need to scale the Deployment down first while you edit it.

---

## 1. Setup (run as instructor / before the exercise)

Works on a single-node cluster (kind, minikube, k3s) or a multi-node cluster
(it pins the app to one node so the maths is the same everywhere).

Save as `setup.sh`, then run `bash setup.sh [node-name]`.

**How the capacity is fixed:** the script measures what is free on the node,
then starts a `capacity-reserver` Deployment (namespace `lab-filler`) that
holds all of it except about **340m CPU / 680Mi memory**. That makes the
answer the same on any node: each WordPress Pod's fair share is about
113m / 226Mi, so **100m CPU / 200Mi memory** (with a ~10% margin) works, and
anything much bigger does not fit. The node needs at least ~360m / ~700Mi
free before the lab starts.

```bash
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
```

**Expected broken state**

```bash
kubectl get pods -n relative-fawn -o wide
# 1 Running, 2 Pending, all on the same node

kubectl get pods -n lab-filler
# capacity-reserver 1/1 Running (holds the rest of the node: leave it alone)

kubectl describe pod -n relative-fawn <pending-pod> | grep -A3 Events
# 0/N nodes are available: Insufficient cpu / Insufficient memory
```

---

## 2. Hints (reveal one at a time)

1. `kubectl describe node <node>` shows **Allocatable** and **Allocated resources**.
2. Other Pods on the node (kube-system, CNI, and the `capacity-reserver`
   in `lab-filler`) already reserve requests. Only the *free* amount can be
   shared, so use `Allocatable` minus `Allocated resources`.
3. The scheduler uses the *effective* Pod request: the larger of
   (highest single init container, since they run one after another) and
   (sum of app containers). Set every container the same, otherwise one
   leftover high value keeps the Pods Pending.
   Note that `init-setup` already looks fine (250m / 500Mi) but is a trap in
   the other direction: its limits (500m / 1000Mi) cap what you can request.
4. Scaling to 0 first makes the "Allocated resources" figure clean:
   `kubectl scale deploy wordpress -n relative-fawn --replicas=0`

---

## 3. Solution

### Step 1: scale down and inspect the node
```bash
kubectl scale deploy wordpress -n relative-fawn --replicas=0

NODE=$(kubectl get nodes -l lab-relative-fawn=true -o jsonpath='{.items[0].metadata.name}')
kubectl describe node $NODE | grep -A8 "Allocatable"
kubectl describe node $NODE | grep -A10 "Allocated resources"
```

### Step 2: calculate
```
free      = allocatable - already requested (other Pods)
per Pod   = free / 3
with margin (~10-15%) -> round down
```

With this lab's setup, `describe node` shows about **340m CPU / 680Mi** left
once the `capacity-reserver` is counted in "Allocated resources":

| | CPU | Memory |
|---|---|---|
| Free for the 3 Pods | ~340m | ~680Mi |
| Per Pod (free / 3) | ~113m | ~226Mi |
| With ~10% margin | **100m** | **200Mi** |

### Step 3: edit the Deployment (both containers, same values)
```bash
kubectl edit deploy wordpress -n relative-fawn
```
Or with a patch:
```bash
kubectl patch deploy wordpress -n relative-fawn --type=json -p='[
 {"op":"replace","path":"/spec/template/spec/initContainers/0/resources/requests/cpu","value":"100m"},
 {"op":"replace","path":"/spec/template/spec/initContainers/0/resources/requests/memory","value":"200Mi"},
 {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"100m"},
 {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"200Mi"}
]'
```

> 100m / 200Mi is under `init-setup`'s limits (500m / 1000Mi), so no limit
> change is needed. If you ever request more than a limit, raise that limit to
> at least the new request, otherwise Pod creation is rejected.

### Step 4: scale back up
```bash
kubectl scale deploy wordpress -n relative-fawn --replicas=3
kubectl rollout status deploy/wordpress -n relative-fawn
```

---

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash
NS=relative-fawn
NODE=$(kubectl get nodes -l lab-relative-fawn=true -o jsonpath='{.items[0].metadata.name}')

ready=$(kubectl get deploy wordpress -n $NS -o jsonpath='{.status.readyReplicas}')
[[ "$ready" == "3" ]] && echo "PASS: 3/3 replicas ready" || echo "FAIL: ready replicas = ${ready:-0}"

reqs=$(kubectl get deploy wordpress -n $NS -o jsonpath='{range .spec.template.spec.initContainers[*]}{.name}={.resources.requests.cpu}/{.resources.requests.memory}{"\n"}{end}{range .spec.template.spec.containers[*]}{.name}={.resources.requests.cpu}/{.resources.requests.memory}{"\n"}{end}')
echo "$reqs"
uniq_count=$(echo "$reqs" | cut -d= -f2 | sort -u | wc -l)
[[ "$uniq_count" == "1" ]] \
  && echo "PASS: init-setup and wordpress requests match" \
  || echo "FAIL: containers have different requests"

# Fair share with the standard setup: ~340m / ~680Mi free -> ~113m / ~226Mi each
FAIR_CPU=113; FAIR_MEM=226
cpu_req=$(kubectl get deploy wordpress -n $NS -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
mem_req=$(kubectl get deploy wordpress -n $NS -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')
if [[ "$cpu_req" == *m && "$mem_req" == *Mi ]]; then
  c=${cpu_req%m}; m=${mem_req%Mi}
  (( c <= FAIR_CPU && c >= FAIR_CPU * 70 / 100 )) \
    && echo "PASS: CPU request ${c}m is a fair share (about $((FAIR_CPU * 70 / 100))m-${FAIR_CPU}m)" \
    || echo "FAIL: CPU request ${c}m is outside the fair share (about $((FAIR_CPU * 70 / 100))m-${FAIR_CPU}m)"
  (( m <= FAIR_MEM && m >= FAIR_MEM * 70 / 100 )) \
    && echo "PASS: memory request ${m}Mi is a fair share (about $((FAIR_MEM * 70 / 100))Mi-${FAIR_MEM}Mi)" \
    || echo "FAIL: memory request ${m}Mi is outside the fair share (about $((FAIR_MEM * 70 / 100))Mi-${FAIR_MEM}Mi)"
else
  echo "WARN: use m (CPU) and Mi (memory) units so the fair-share check can run"
fi

echo
echo "Node allocation:"
kubectl describe node $NODE | grep -A10 "Allocated resources"
```

Success criteria:

- All 3 Pods `Running`.
- The init container and the main container have identical requests
  (and no request exceeds its limit).
- Each Pod's requests are a fair third of the free capacity: about 80-113m CPU
  and 160-226Mi memory with the standard setup (100m / 200Mi is the intended answer).
- `capacity-reserver` in `lab-filler` is untouched.
- The node's CPU/memory request percentages are below 100%.

---

## 5. Cleanup
```bash
kubectl delete namespace relative-fawn lab-filler --ignore-not-found
kubectl label node --all lab-relative-fawn-
```

## 6. Optional extensions

- Add a `mysql` Deployment and split the node between both apps (e.g. 60/40).
- Add a sidecar container and divide each Pod's share across all containers.
- Add matching `limits` and discuss QoS classes (Burstable vs Guaranteed).
- Add a `ResourceQuota` in `relative-fawn` and see how it interacts with requests.
