## Solution
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
