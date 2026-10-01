#!/usr/bin/env bash
# Starting state: Deployment "synergy-leverager" with ONE container that writes
# a log loop to /var/log/synergy-leverager.log inside its own container filesystem.
# No Volume exists yet, and there is no sidecar - that's the task.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f deployment.yaml
kubectl rollout status deploy/synergy-leverager --timeout=60s

echo
kubectl get deploy synergy-leverager
echo
echo "Lab ready. Deployment has ONE container and NO volumes."
echo "Your task: add a 'sidecar' container (see TASK.md) without touching anything"
echo "else on the existing container except its volumeMounts."
