#!/usr/bin/env bash
set -euo pipefail
kubectl config use-context kind-cni-lab

# 1. Operator + CRDs
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml

# 2. Tell the operator to actually install Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml

echo "Waiting for Calico to become ready (can take a few minutes)..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl -n calico-system wait --for=condition=Ready pod -l k8s-app=calico-node --timeout=300s

echo
echo "--- Proving NetworkPolicy enforcement actually works ---"
kubectl create ns netpol-test --dry-run=client -o yaml | kubectl apply -f -
kubectl -n netpol-test run web --image=nginx:alpine --port=80 --expose
kubectl -n netpol-test run client --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl -n netpol-test wait --for=condition=Ready pod/web pod/client --timeout=60s

echo "Before policy (should succeed):"
kubectl -n netpol-test exec client -- wget -qO- --timeout=5 http://web && echo "  -> reached web (expected)"

kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
YAML

echo "After default-deny policy (should fail/timeout):"
kubectl -n netpol-test exec client -- wget -qO- --timeout=5 http://web \
  && echo "  -> UNEXPECTED: still reached web (NetworkPolicy not enforced!)" \
  || echo "  -> blocked as expected: NetworkPolicy IS enforced"
