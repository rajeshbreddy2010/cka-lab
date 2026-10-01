#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
kubectl delete pod big-corp-app --ignore-not-found --now
kubectl apply -f solution.yaml
kubectl wait --for=condition=Ready pod/big-corp-app --timeout=60s
echo
echo "Tailing sidecar logs (Ctrl+C to stop)..."
kubectl logs big-corp-app -c sidecar --tail=5 -f
