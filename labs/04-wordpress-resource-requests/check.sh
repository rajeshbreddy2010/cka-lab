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

# Fair share with the standard setup: ~340m / ~680Mi free -> ~113m / ~226Mi each
FAIR_CPU=113; FAIR_MEM=226
cpu_req=$(kubectl get deploy wordpress -n $NS -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
mem_req=$(kubectl get deploy wordpress -n $NS -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')
if [[ "$cpu_req" == *m && "$mem_req" == *Mi ]]; then
  c=${cpu_req%m}; m=${mem_req%Mi}
  (( c <= FAIR_CPU && c >= FAIR_CPU * 70 / 100 )) \
    && echo "PASS: CPU request ${c}m is a fair share (about $((FAIR_CPU * 70 / 100))m-${FAIR_CPU}m)" \
    || echo "FAIL: CPU request ${c}m is outside the fair share (about $((FAIR_CPU * 70 / 100))m-${FAIR_CPU}m)"
  (( m <= FAIR_MEM && m >= FAIR_MEM * 70 / 100 )) \
    && echo "PASS: memory request ${m}Mi is a fair share (about $((FAIR_MEM * 70 / 100))Mi-${FAIR_MEM}Mi)" \
    || echo "FAIL: memory request ${m}Mi is outside the fair share (about $((FAIR_MEM * 70 / 100))Mi-${FAIR_MEM}Mi)"
else
  echo "WARN: use m (CPU) and Mi (memory) units so the fair-share check can run"
fi

echo
echo "Node allocation:"
kubectl describe node $NODE | grep -A10 "Allocated resources"
