# Lab: Choose and Apply the Right NetworkPolicy (`frontend` / `backend`)

## Scenario
A `frontend` Deployment (namespace `frontend`) needs to reach a `backend`
Deployment (namespace `backend`). Several candidate NetworkPolicy YAML files
already exist on disk in `~/netpol`, written by a previous engineer. Some are
wrong, and one is dangerously permissive. Only one is correct.

## Task
Review and apply the appropriate NetworkPolicy from the provided YAML
samples. Ensure the chosen NetworkPolicy is **not overly permissive**, but
allows communication between the `frontend` and `backend` Deployments,
running in the `frontend` and `backend` namespaces respectively.

1. First, analyze the `frontend` and `backend` Deployments to determine the
   specific requirements for the NetworkPolicy that needs to be applied.
2. Next, examine the NetworkPolicy YAML samples in `~/netpol`.
3. **Do not delete or modify the provided samples. Only apply one of them.**
   Failure to comply may result in a reduced score.
4. Finally, apply the NetworkPolicy that enables communication between the
   `frontend` and `backend` Deployments, without being overly permissive.

---

## 0. Prerequisite: a CNI that enforces NetworkPolicy

`NetworkPolicy` objects are inert unless the cluster's CNI plugin enforces
them. Plain `kindnet` (kind's default) and plain `flannel` do **not**
enforce policies — everything will still be reachable no matter what you
apply, which makes the exercise unverifiable. Use a CNI that does, e.g.
Calico:

```bash
# kind cluster created with networking disabled, then Calico installed
kind create cluster --config kind-no-cni.yaml   # disableDefaultCNI: true
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```

Most managed exam environments already have this configured. If you're
building this at home and traffic is never blocked no matter what you
apply, check your CNI first before assuming your policy is wrong.

---

## 1. Setup (run as instructor / before the exercise)

```bash
#!/usr/bin/env bash
set -euo pipefail

for NS in frontend backend other; do
  kubectl delete namespace "$NS" --ignore-not-found --wait=true
  kubectl create namespace "$NS"
done

# ---------- backend ----------
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: backend
  labels:
    app: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: hashicorp/http-echo:1.0
        args: ["-listen=:8080", "-text=hello from backend"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: backend
spec:
  selector:
    app: backend
  ports:
  - port: 8080
    targetPort: 8080
EOF

# ---------- frontend ----------
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: frontend
  labels:
    app: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: curlimages/curl:8.10.1
        command: ["sh", "-c", "sleep infinity"]
EOF

# ---------- a third, unrelated namespace to prove the policy isn't overly permissive ----------
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prober
  namespace: other
  labels:
    app: prober
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prober
  template:
    metadata:
      labels:
        app: prober
    spec:
      containers:
      - name: prober
        image: curlimages/curl:8.10.1
        command: ["sh", "-c", "sleep infinity"]
EOF

kubectl rollout status deploy/backend -n backend --timeout=60s
kubectl rollout status deploy/frontend -n frontend --timeout=60s
kubectl rollout status deploy/prober -n other --timeout=60s

# ---------- NetworkPolicy sample files ----------
mkdir -p ~/netpol

cat <<'EOF' > ~/netpol/01-deny-all.yaml
# Denies ALL ingress to backend Pods, including from frontend.
# Too restrictive: applying this breaks the required communication.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
    - Ingress
EOF

cat <<'EOF' > ~/netpol/02-allow-all-ingress.yaml
# Allows ingress to backend Pods from ANY namespace, ANY pod, ANY port.
# Works, but is overly permissive -- do not choose this one.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-ingress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - {}
EOF

cat <<'EOF' > ~/netpol/03-allow-frontend-wrong-port.yaml
# Correct selectors, but the port doesn't match the backend container port.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-wrong-port
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: frontend
      ports:
        - protocol: TCP
          port: 80
EOF

cat <<'EOF' > ~/netpol/04-allow-wrong-pod-selector.yaml
# Namespace selector is correct, but podSelector matches no real Pods
# in this cluster (there is no Pod labeled app=backend-legacy).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-wrong-pod-selector
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend-legacy
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: frontend
      ports:
        - protocol: TCP
          port: 8080
EOF

cat <<'EOF' > ~/netpol/05-allow-frontend-to-backend.yaml
# Correct: scoped to backend Pods, only from the frontend namespace,
# only on the port the backend actually listens on.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: frontend
          podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
EOF

echo
echo "Setup complete."
echo "  ~/netpol now has 5 sample policies. None are applied yet."
echo "  kubectl get netpol -n backend      # should show none"
echo "  kubectl exec -n frontend deploy/frontend -- curl -s -m3 backend.backend.svc.cluster.local:8080"
```

**Expected starting state**

```bash
ls ~/netpol
# 01-deny-all.yaml
# 02-allow-all-ingress.yaml
# 03-allow-frontend-wrong-port.yaml
# 04-allow-wrong-pod-selector.yaml
# 05-allow-frontend-to-backend.yaml

kubectl get networkpolicy -n backend
# No resources found (nothing applied yet -- traffic is currently unrestricted)
```

---

## 2. Hints (reveal one at a time)

1. Start by reading, not applying: `cat ~/netpol/*.yaml` or open each file.
2. Find the backend's real container port:
   `kubectl get deploy backend -n backend -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'`
3. Find the backend's real Pod label:
   `kubectl get deploy backend -n backend -o jsonpath='{.spec.template.metadata.labels}'`
4. Find the frontend namespace's label that a `namespaceSelector` would
   match: `kubectl get ns frontend --show-labels`. Every namespace has the
   built-in `kubernetes.io/metadata.name=<namespace name>` label, which is
   the most reliable one to select on.
5. A policy that "works" isn't automatically correct — one of the samples
   allows all ingress from everywhere, which technically permits
   frontend-to-backend traffic too, but the task explicitly forbids being
   overly permissive.
6. A `podSelector` that doesn't match any real Pods' labels means the policy
   silently applies to zero Pods — check labels character-for-character.
7. Once you've picked the right file, apply just that one:
   `kubectl apply -f ~/netpol/<file>.yaml`. Don't edit or delete the others.

---

## 3. Solution

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

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash

count=$(kubectl get networkpolicy -n backend --no-headers 2>/dev/null | wc -l)
[[ "$count" == "1" ]] && echo "PASS: exactly one NetworkPolicy applied in backend" \
  || echo "FAIL: $count NetworkPolicies found in backend (expected exactly 1)"

name=$(kubectl get networkpolicy -n backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[[ "$name" == "allow-frontend-to-backend" ]] \
  && echo "PASS: the correct policy (allow-frontend-to-backend) is applied" \
  || echo "FAIL: applied policy is '${name:-none}', expected allow-frontend-to-backend"

# Make sure ingress isn't allowed from everywhere (i.e. no empty 'from')
empty_from=$(kubectl get networkpolicy "$name" -n backend -o jsonpath='{.spec.ingress[0].from}' 2>/dev/null)
[[ "$empty_from" != "[{}]" && -n "$empty_from" ]] \
  && echo "PASS: ingress is scoped (not an open 'allow from anywhere' rule)" \
  || echo "FAIL: ingress rule looks unscoped -- check for overly permissive 'from: [{}]'"

# Sample files must be untouched
missing=0
for f in 01-deny-all 02-allow-all-ingress 03-allow-frontend-wrong-port 04-allow-wrong-pod-selector 05-allow-frontend-to-backend; do
  [[ -f ~/netpol/$f.yaml ]] || { echo "FAIL: ~/netpol/$f.yaml is missing"; missing=1; }
done
[[ "$missing" == "0" ]] && echo "PASS: all sample files are still present in ~/netpol"

echo
echo "Connectivity checks:"
kubectl exec -n frontend deploy/frontend -- curl -s -m3 backend.backend.svc.cluster.local:8080 \
  && echo "PASS: frontend can reach backend" || echo "FAIL: frontend cannot reach backend"
kubectl exec -n other deploy/prober -- curl -s -m3 backend.backend.svc.cluster.local:8080 \
  && echo "FAIL: unrelated namespace 'other' can also reach backend -- too permissive" \
  || echo "PASS: unrelated namespace 'other' is correctly blocked"
```

Success criteria:

- Exactly one NetworkPolicy exists in `backend`, and it is
  `allow-frontend-to-backend`.
- Its ingress rule is scoped to the `frontend` namespace (and ideally the
  `frontend` Pod label too), not an open `from: [{}]`.
- All 5 sample files in `~/netpol` are unmodified and still present.
- `frontend` can reach `backend` on port 8080; the unrelated `other`
  namespace cannot.

---

## 5. Cleanup
```bash
kubectl delete namespace frontend backend other
rm -rf ~/netpol
```

## 6. Optional extensions

- Add an egress-side policy in `frontend` that only allows egress to
  `backend` on 8080 (plus DNS on port 53), for defense in depth on both
  sides of the connection.
- Add a 6th sample that scopes correctly but omits `policyTypes: [Ingress]`
  — discuss why that field is easy to forget and what happens without it.
- Turn `backend`'s podSelector into a multi-value `matchExpressions` rule
  and have the candidate translate the same intent into that syntax.
- Practice the reverse case: a policy correct in every way except it's
  created in the `frontend` namespace instead of `backend` (ingress rules
  belong on the *destination* Pods' namespace).
