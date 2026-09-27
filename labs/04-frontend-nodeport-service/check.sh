#!/usr/bin/env bash
NS=spline-reticulator

cp=$(kubectl get deploy front-end -n $NS -o jsonpath='{.spec.template.spec.containers[?(@.name=="nginx")].ports[0].containerPort}')
[[ "$cp" == "80" ]] && echo "PASS: nginx container declares containerPort 80" \
  || echo "FAIL: nginx containerPort is '${cp:-unset}'"

svc_type=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.type}' 2>/dev/null)
[[ "$svc_type" == "NodePort" ]] && echo "PASS: front-end-svc is type NodePort" \
  || echo "FAIL: front-end-svc type is '${svc_type:-missing}'"

port=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.ports[0].port}')
tport=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.ports[0].targetPort}')
nport=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.ports[0].nodePort}')
[[ "$port" == "80" && "$tport" == "80" ]] && echo "PASS: Service port/targetPort are 80/80" \
  || echo "FAIL: Service port=$port targetPort=$tport"
[[ -n "$nport" && "$nport" -ge 30000 && "$nport" -le 32767 ]] 2>/dev/null \
  && echo "PASS: nodePort $nport is allocated" || echo "FAIL: nodePort missing or out of range"

sel=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.selector.app}')
[[ "$sel" == "front-end" ]] && echo "PASS: selector matches Deployment Pods" \
  || echo "FAIL: selector is '${sel:-missing}'"

eps=$(kubectl get endpoints front-end-svc -n $NS -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
[[ "$eps" -ge 1 ]] && echo "PASS: Service has $eps endpoint(s)" \
  || echo "FAIL: no endpoints — check selector/labels/readiness"
