#!/usr/bin/env bash
NS=autoscale

target=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null)
kind=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.scaleTargetRef.kind}' 2>/dev/null)
[[ "$target" == "apache-server" && "$kind" == "Deployment" ]] \
  && echo "PASS: HPA targets Deployment/apache-server" \
  || echo "FAIL: HPA targets $kind/$target"

minr=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.minReplicas}')
maxr=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.maxReplicas}')
[[ "$minr" == "1" && "$maxr" == "4" ]] \
  && echo "PASS: minReplicas=1, maxReplicas=4" \
  || echo "FAIL: minReplicas=$minr maxReplicas=$maxr"

util=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}')
[[ "$util" == "50" ]] && echo "PASS: CPU target is 50%" || echo "FAIL: CPU target is '${util:-unset}'"

window=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}')
[[ "$window" == "30" ]] && echo "PASS: downscale stabilization window is 30s" \
  || echo "FAIL: stabilization window is '${window:-unset}'"

req=$(kubectl get deploy apache-server -n $NS -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
[[ -n "$req" ]] && echo "PASS: apache-server container has a CPU request ($req), so % utilization is meaningful" \
  || echo "FAIL: apache-server container has no CPU request set"

cur=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
[[ -n "$cur" ]] && echo "PASS: metrics-server is reporting a current value ($cur%)" \
  || echo "WARN: current utilization not reported yet -- check metrics-server is installed and has scraped at least once"
