#!/usr/bin/env bash
# Starting state: a bare Pod "big-corp-app" (NOT a Deployment) that writes a log
# loop to /var/log/big-corp-app.log inside its own container filesystem.
# No Volume exists yet - that's the point of the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl delete pod big-corp-app --ignore-not-found --now >/dev/null 2>&1 || true
kubectl apply -f pod.yaml
kubectl wait --for=condition=Ready pod/big-corp-app --timeout=60s

echo
kubectl get pod big-corp-app
echo
echo "Lab ready. Pod has ONE container and NO volumes."
echo "Your task: add a 'sidecar' container (see TASK.md) without losing the running log."
