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

```bash
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
```

**Expected broken state**

```bash
kubectl get pods -n relative-fawn -o wide
# 1 Running, 2 Pending, all on the same node

kubectl describe pod -n relative-fawn <pending-pod> | grep -A3 Events
# 0/N nodes are available: Insufficient cpu / Insufficient memory
```

---

## 2. Hints (reveal one at a time)

1. `kubectl describe node <node>` shows **Allocatable** and **Allocated resources**.
2. Other Pods on the node (kube-system, CNI, etc.) already reserve some
   requests. Only the *free* amount can be shared.
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

Worked example (node: 2000m CPU, 3800Mi allocatable; 500m CPU / 600Mi already requested):

| | CPU | Memory |
|---|---|---|
| Free | 1500m | 3200Mi |
| Per Pod (free / 3) | 500m | ~1066Mi |
| With ~10% margin | **450m** | **950Mi** |

### Step 3: edit the Deployment (both containers, same values)
```bash
kubectl edit deploy wordpress -n relative-fawn
```
Or with a patch:
```bash
kubectl patch deploy wordpress -n relative-fawn --type=json -p='[
 {"op":"replace","path":"/spec/template/spec/initContainers/0/resources/requests/cpu","value":"450m"},
 {"op":"replace","path":"/spec/template/spec/initContainers/0/resources/requests/memory","value":"950Mi"},
 {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"450m"},
 {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"950Mi"}
]'
```

> The worked example (450m / 950Mi) stays under `init-setup`'s limits
> (500m / 1000Mi), so no limit change is needed. On a larger node where your
> share is higher, also patch `initContainers/0/resources/limits` to at least
> the new request, otherwise the Deployment will be rejected/fail to create Pods.

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

echo
echo "Node allocation:"
kubectl describe node $NODE | grep -A10 "Allocated resources"
```

Success criteria:

- All 3 Pods `Running`.
- The init container and the main container have identical requests
  (and no request exceeds its limit).
- Requests are roughly an equal third of the free node capacity, with some headroom left.
- The node's CPU/memory request percentages are below 100%.

---

## 5. Cleanup
```bash
kubectl delete namespace relative-fawn
kubectl label node --all lab-relative-fawn-
```

## 6. Optional extensions

- Add a `mysql` Deployment and split the node between both apps (e.g. 60/40).
- Add a sidecar container and divide each Pod's share across all containers.
- Add matching `limits` and discuss QoS classes (Burstable vs Guaranteed).
- Add a `ResourceQuota` in `relative-fawn` and see how it interacts with requests.
