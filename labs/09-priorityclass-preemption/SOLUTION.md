## Solution
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
