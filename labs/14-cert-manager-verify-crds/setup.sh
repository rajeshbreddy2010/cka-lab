#!/usr/bin/env bash
set -euo pipefail

CM_VERSION=v1.15.3

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CM_VERSION}/cert-manager.yaml"

kubectl rollout status deploy/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deploy/cert-manager-webhook -n cert-manager --timeout=120s
kubectl rollout status deploy/cert-manager-cainjector -n cert-manager --timeout=120s

# Make sure the target files don't exist yet
rm -f ~/resources.yaml ~/subject.yaml

echo
echo "Setup complete. Check with:"
echo "  kubectl get pods -n cert-manager"
echo "  kubectl get crd | grep cert-manager"
