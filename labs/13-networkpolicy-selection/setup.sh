#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

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
