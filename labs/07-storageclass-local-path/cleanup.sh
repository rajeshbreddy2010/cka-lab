#!/usr/bin/env bash
kubectl delete ns storage-lab --ignore-not-found
kubectl delete pv data-pv --ignore-not-found
kubectl delete sc local-path --ignore-not-found
rm -f .baseline
