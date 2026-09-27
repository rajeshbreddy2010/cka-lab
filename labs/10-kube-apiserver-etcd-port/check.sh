#!/usr/bin/env bash

port_check=$(grep -o -- '--etcd-servers=[^ "]*' /etc/kubernetes/manifests/kube-apiserver.yaml)
echo "$port_check" | grep -q ':2380' \
  && echo "FAIL: manifest still references etcd peer port 2380: $port_check" \
  || echo "PASS: manifest no longer points at port 2380"
echo "$port_check" | grep -q ':2379' \
  && echo "PASS: manifest points at etcd client port 2379" \
  || echo "FAIL: manifest doesn't reference port 2379 at all -- check --etcd-servers"

if kubectl get nodes >/dev/null 2>&1; then
  echo "PASS: kubectl can reach the apiserver"
else
  echo "FAIL: kubectl still cannot reach the apiserver"
fi

state=$(crictl ps --name kube-apiserver -o json 2>/dev/null | grep -o '"state": *"[A-Z_]*"' | head -1)
echo "$state" | grep -q RUNNING \
  && echo "PASS: kube-apiserver container is Running" \
  || echo "FAIL: kube-apiserver container state: ${state:-not found}"

ready=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
echo "$ready" | grep -q False \
  && echo "FAIL: at least one node is NotReady" \
  || echo "PASS: all visible nodes report Ready"
