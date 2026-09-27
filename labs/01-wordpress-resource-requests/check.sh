#!/usr/bin/env bash
NS=relative-fawn
NODE=$(kubectl get nodes -l lab-relative-fawn=true -o jsonpath='{.items[0].metadata.name}')

ready=$(kubectl get deploy wordpress -n $NS -o jsonpath='{.status.readyReplicas}')
[[ "$ready" == "3" ]] && echo "PASS: 3/3 replicas ready" || echo "FAIL: ready replicas = ${ready:-0}"

reqs=$(kubectl get deploy wordpress -n $NS -o jsonpath='{range .spec.template.spec.initContainers[*]}{.name}={.resources.requests.cpu}/{.resources.requests.memory}{"\n"}{end}{range .spec.template.spec.containers[*]}{.name}={.resources.requests.cpu}/{.resources.requests.memory}{"\n"}{end}')
echo "$reqs"
uniq_count=$(echo "$reqs" | cut -d= -f2 | sort -u | wc -l)
[[ "$uniq_count" == "1" ]] \
  && echo "PASS: init-setup and wordpress requests match" \
  || echo "FAIL: containers have different requests"

echo
echo "Node allocation:"
kubectl describe node $NODE | grep -A10 "Allocated resources"
