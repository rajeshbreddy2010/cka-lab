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
