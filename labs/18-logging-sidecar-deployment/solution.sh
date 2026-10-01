#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
kubectl apply -f solution.yaml
kubectl rollout status deploy/synergy-leverager --timeout=60s
echo
echo "Tailing sidecar logs (Ctrl+C to stop)..."
kubectl logs deploy/synergy-leverager -c sidecar --tail=5 -f
