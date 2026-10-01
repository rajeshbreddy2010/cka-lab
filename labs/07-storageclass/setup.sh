#!/usr/bin/env bash
# Builds the starting state for Question 14:
#   - a StorageClass "local-path" (rancher.io/local-path) marked as DEFAULT
#   - an existing PVC + Deployment that you must NOT modify
set -euo pipefail
cd "$(dirname "$0")"

if ! kubectl get ns local-path-storage >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
fi
kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s

# Make sure local-path exists and is the default (the "trap" you must undo)
if ! kubectl get sc local-path >/dev/null 2>&1; then
  kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
YAML
fi
kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Clean any previous attempt at the answer
kubectl delete sc local-storage --ignore-not-found

# Existing workload (must stay untouched)
kubectl apply -f existing-app.yaml
kubectl -n storage-lab rollout status deploy/data-app --timeout=120s

# Baseline for verify.sh
{
  echo "DEPLOY_GEN=$(kubectl -n storage-lab get deploy data-app -o jsonpath='{.metadata.generation}')"
  echo "DEPLOY_UID=$(kubectl -n storage-lab get deploy data-app -o jsonpath='{.metadata.uid}')"
  echo "PVC_UID=$(kubectl -n storage-lab get pvc data-pvc -o jsonpath='{.metadata.uid}')"
  echo "PVC_SC=$(kubectl -n storage-lab get pvc data-pvc -o jsonpath='{.spec.storageClassName}')"
} > .baseline

echo
kubectl get sc
echo
echo "Lab ready. Create StorageClass 'local-storage', make it the ONLY default. Don't touch storage-lab resources."
