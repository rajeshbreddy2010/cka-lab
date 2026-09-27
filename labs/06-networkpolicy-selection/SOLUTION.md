## Solution
### Step 1: gather the facts
```bash
kubectl get deploy backend -n backend -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
# {"app":"backend"}

kubectl get deploy backend -n backend -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}{"\n"}'
# 8080

kubectl get deploy frontend -n frontend -o jsonpath='{.spec.template.metadata.labels}{"\n"}'
# {"app":"frontend"}

kubectl get ns frontend --show-labels
# kubernetes.io/metadata.name=frontend
```

So the correct policy must: target Pods labeled `app: backend` in the
`backend` namespace, allow ingress only from the `frontend` namespace
(ideally also scoped to `app: frontend` Pods within it), only on TCP port
`8080`.

### Step 2: examine the samples
```bash
for f in ~/netpol/*.yaml; do echo "== $f =="; cat "$f"; echo; done
```

| File | Verdict |
|---|---|
| `01-deny-all.yaml` | Blocks everything, including frontend. Wrong. |
| `02-allow-all-ingress.yaml` | Works, but allows any namespace/any port — overly permissive. Wrong for this task. |
| `03-allow-frontend-wrong-port.yaml` | Right selectors, port `80` instead of `8080`. Wrong. |
| `04-allow-wrong-pod-selector.yaml` | `podSelector` targets `app: backend-legacy`, which matches no Pods. Wrong. |
| `05-allow-frontend-to-backend.yaml` | Correct pod selector, correct namespace + pod selector on the source, correct port. **This one.** |

### Step 3: apply only the correct one
```bash
kubectl apply -f ~/netpol/05-allow-frontend-to-backend.yaml
```

Do **not** run `kubectl apply -f ~/netpol/` (applies all 5) and do not
modify or delete the other files — the task penalizes that.

### Step 4: verify
```bash
kubectl get networkpolicy -n backend
```

Frontend can reach backend:
```bash
kubectl exec -n frontend deploy/frontend -- curl -s -m3 backend.backend.svc.cluster.local:8080
# hello from backend
```

An unrelated namespace cannot (proving it isn't overly permissive):
```bash
kubectl exec -n other deploy/prober -- curl -s -m3 backend.backend.svc.cluster.local:8080
# (times out / no response)
```

---
