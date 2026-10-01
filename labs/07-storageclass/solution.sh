#!/usr/bin/env bash
set -e
# 1. Create the StorageClass (NOT default yet)
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
YAML

# 2. Patch it to be the default
kubectl patch sc local-storage -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 3. Make sure it is the ONLY default: un-default every other class
for sc in $(kubectl get sc -o name | grep -v 'local-storage$'); do
  kubectl patch "$sc" -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
done

kubectl get sc
