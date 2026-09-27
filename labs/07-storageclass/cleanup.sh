#!/usr/bin/env bash
kubectl delete ns storage-lab test-default --ignore-not-found
kubectl delete sc local-storage --ignore-not-found
kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null
rm -f .baseline
