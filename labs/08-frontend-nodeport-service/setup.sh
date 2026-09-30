#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NS=spline-reticulator

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: front-end
  namespace: $NS
  labels:
    app: front-end
spec:
  replicas: 2
  selector:
    matchLabels:
      app: front-end
  template:
    metadata:
      labels:
        app: front-end
    spec:
      containers:
      - name: nginx
        image: nginx:stable
EOF

kubectl rollout status deploy/front-end -n "$NS" --timeout=60s

echo
echo "Done. Deployment 'front-end' has no containerPort declared and no Service yet:"
echo "  kubectl get deploy front-end -n $NS -o yaml | grep -A3 containers:"
echo "  kubectl get svc -n $NS"
