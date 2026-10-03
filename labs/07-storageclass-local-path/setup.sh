#!/usr/bin/env bash
# Starting state:
#   - the rancher.io/local-path PROVISIONER (controller) is running
#   - but its StorageClass object does NOT exist (deleted on purpose)
#   - an existing PVC + Deployment (bound via a manual PV) that you must not touch
set -euo pipefail
cd "$(dirname "$0")"

if ! kubectl get ns local-path-storage >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
fi
kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s

# The upstream manifest creates its own default "local-path" StorageClass -
# delete it so the starting state has the controller but NO StorageClass,
# matching "an existing provisioner" with no class pointing at it yet.
kubectl delete sc local-path --ignore-not-found

mkdir -p /tmp/storage-lab-data
kubectl apply -f existing-app.yaml
kubectl -n storage-lab rollout status deploy/data-app --timeout=120s

{
  echo "DEPLOY_GEN=$(kubectl -n storage-lab get deploy data-app -o jsonpath='{.metadata.generation}')"
  echo "PVC_UID=$(kubectl -n storage-lab get pvc data-pvc -o jsonpath='{.metadata.uid}')"
} > .baseline

echo
kubectl get sc
echo
echo "Lab ready. No StorageClass exists yet. Create 'local-path' and make it the default."
echo "Don't touch anything in namespace storage-lab."
