# Lab: PriorityClass and Pod preemption (namespace `priority`)

## Scenario
The `priority` namespace runs several workloads on a node that is almost
full. The `busybox-logger` Deployment is important and cannot get all of its
Pods scheduled. You need to give it a higher priority than the other workloads.

## Task
1. Create a new PriorityClass named `high-priority` for user workloads with a
   value that is **one less than the highest existing user-defined**
   PriorityClass value.
2. Patch the existing Deployment `busybox-logger` running in the `priority`
   namespace to use the `high-priority` PriorityClass.
3. Ensure that the `busybox-logger` Deployment rolls out successfully with the
   new PriorityClass set.

It is expected that Pods from other Deployments running in the `priority`
namespace are evicted.

**Do not modify other Deployments running in the `priority` namespace.**
Failure to do so may result in a reduced score.

---

## 1. Setup (run as instructor / before the exercise)

**Your cluster right now** (only the built-in system classes exist):

```
root@controlplane:~$ k get priorityClass
NAME                      VALUE        GLOBAL-DEFAULT   AGE   PREEMPTIONPOLICY
system-cluster-critical   2000000000   false            30d   PreemptLowerPriority
system-node-critical      2000001000   false            30d   PreemptLowerPriority
```

Because there are no user-defined classes yet, the setup creates them so the
task ("one less than the highest existing user-defined value") has something
to work with. It also skips the control-plane node (it is normally tainted
`NoSchedule`) and uses a worker such as `node01`. To force a node:
`bash setup.sh node01`.

Works on a single-node cluster (kind, minikube, k3s) or a multi-node cluster
(it pins the workloads to one node). It:

- creates 3 user-defined PriorityClasses (the highest is deliberately not the
  obvious one),
- fills about 56% of the node's *free* capacity with two "other" Deployments,
- creates `busybox-logger` (3 replicas) asking for 60% of the free capacity,
  so one replica stays Pending.

Save as `setup.sh`, then run `bash setup.sh [node-name]`.

```bash
#!/usr/bin/env bash
set -euo pipefail

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
```

**Expected starting state**

```bash
kubectl get priorityclass
# system-cluster-critical   2000000000
# system-node-critical      2000001000
# batch-low                 1000
# standard-user             50000
# business-critical         250000      <- highest USER-defined value

kubectl get pods -n priority
# web-frontend x2 Running, batch-worker x2 Running
# busybox-logger: 2 Running, 1 Pending
```

---

## 2. Hints (reveal one at a time)

1. `kubectl get priorityclass` lists them all, `--sort-by=.value` orders them.
2. The `system-cluster-critical` and `system-node-critical` classes are
   **not** user-defined. Ignore them when finding the highest value.
3. PriorityClass is cluster-scoped, so there is no `-n`.
4. `kubectl create priorityclass --help` shows the flags.
5. The class goes in the **Pod template**: `spec.template.spec.priorityClassName`,
   not at the Deployment's top level.
6. The scheduler preempts (evicts) lower-priority Pods to make room for a
   higher-priority Pod that cannot be scheduled. You don't need to delete
   anything yourself.

---

## 3. Solution

### Step 1: find the highest user-defined value
```bash
kubectl get priorityclass --sort-by=.value
```
Highest non-system value: `250000` (`business-critical`), so the new value is
**249999**.

Optional one-liner:
```bash
kubectl get pc -o jsonpath='{range .items[*]}{.metadata.name} {.value}{"\n"}{end}' \
  | grep -v '^system-' | sort -k2 -n | tail -1
```

### Step 2: create the PriorityClass
```bash
kubectl create priorityclass high-priority --value=249999 \
  --description="High priority for user workloads"
```
Or declaratively:
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 249999
globalDefault: false
description: "High priority for user workloads"
```

### Step 3: patch busybox-logger
```bash
kubectl patch deployment busybox-logger -n priority --type=merge \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
```
Or `kubectl edit deploy busybox-logger -n priority` and add
`priorityClassName: high-priority` under `spec.template.spec`.

### Step 4: watch the rollout
```bash
kubectl rollout status deploy/busybox-logger -n priority
kubectl get pods -n priority -o wide
kubectl get events -n priority --sort-by=.lastTimestamp | grep -i preempt
```
Expected result: `busybox-logger` 3/3 Running, and some `web-frontend` /
`batch-worker` Pods are evicted (their replacements stay Pending because they
have lower priority and there is no room).

> Do **not** scale, edit, or delete `web-frontend` or `batch-worker`. The task
> says their Pods are expected to be evicted by the scheduler.

---

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash
NS=priority

# highest user-defined value, ignoring system classes and high-priority itself
top=$(kubectl get pc -o jsonpath='{range .items[*]}{.metadata.name} {.value}{"\n"}{end}' \
  | grep -v '^system-' | grep -v '^high-priority ' | sort -k2 -n | tail -1 | awk '{print $2}')
expected=$((top - 1))
actual=$(kubectl get pc high-priority -o jsonpath='{.value}' 2>/dev/null)
[[ "$actual" == "$expected" ]] \
  && echo "PASS: high-priority value is $actual (highest user value $top - 1)" \
  || echo "FAIL: high-priority value is '${actual:-missing}', expected $expected"

pc=$(kubectl get deploy busybox-logger -n $NS -o jsonpath='{.spec.template.spec.priorityClassName}')
[[ "$pc" == "high-priority" ]] && echo "PASS: busybox-logger uses high-priority" \
  || echo "FAIL: busybox-logger priorityClassName is '${pc:-unset}'"

ready=$(kubectl get deploy busybox-logger -n $NS -o jsonpath='{.status.readyReplicas}')
[[ "$ready" == "3" ]] && echo "PASS: busybox-logger 3/3 ready" \
  || echo "FAIL: busybox-logger ready replicas = ${ready:-0}"

# other deployments must be untouched (generation 1, replicas 2, no priority class)
for d in web-frontend batch-worker; do
  gen=$(kubectl get deploy $d -n $NS -o jsonpath='{.metadata.generation}')
  rep=$(kubectl get deploy $d -n $NS -o jsonpath='{.spec.replicas}')
  dpc=$(kubectl get deploy $d -n $NS -o jsonpath='{.spec.template.spec.priorityClassName}')
  [[ "$gen" == "1" && "$rep" == "2" && -z "$dpc" ]] \
    && echo "PASS: $d was not modified" \
    || echo "FAIL: $d was modified (generation=$gen replicas=$rep priorityClass='$dpc')"
done

echo
echo "Other Pods (some should now be Pending/evicted):"
kubectl get pods -n $NS
```

Success criteria:

- `high-priority` exists with value **249999**.
- `busybox-logger` uses `high-priority` and all 3 replicas are Running.
- `web-frontend` and `batch-worker` Deployments are unmodified, while some
  of their Pods are evicted or Pending.

---

## 5. Cleanup
```bash
kubectl delete namespace priority
kubectl delete priorityclass high-priority batch-low standard-user business-critical
kubectl label node --all lab-
```

## 6. Optional extensions

- Add `preemptionPolicy: Never` to the PriorityClass and observe that
  `busybox-logger` no longer evicts other Pods (it just gets a better place in
  the scheduling queue).
- Try `globalDefault: true` on a class and see which new Pods inherit it. Only
  one class can be the global default.
- Try a value above 1,000,000,000 and read the API error (reserved for system
  classes).
- Give the "other" Deployments a middle priority (`standard-user`) and see how
  the outcome changes.
