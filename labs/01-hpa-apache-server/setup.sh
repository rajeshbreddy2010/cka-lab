#!/usr/bin/env bash
set -euo pipefail

NS=autoscale

kubectl delete namespace "$NS" --ignore-not-found --wait=true
kubectl create namespace "$NS"

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-server
  namespace: $NS
  labels:
    app: apache-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apache-server
  template:
    metadata:
      labels:
        app: apache-server
    spec:
      containers:
      - name: apache-server
        image: httpd:2.4
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF

kubectl rollout status deploy/apache-server -n "$NS" --timeout=60s

echo
echo "Setup complete."
echo "  kubectl get deploy apache-server -n $NS"
echo "  kubectl get hpa -n $NS   # should show none yet"
