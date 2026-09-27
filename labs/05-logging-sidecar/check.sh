#!/usr/bin/env bash

echo "--- Task A: synergy-leverager ---"
c=$(kubectl get deploy synergy-leverager -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].image}')
[[ "$c" == "busybox:stable" ]] && echo "PASS: sidecar image is busybox:stable" || echo "FAIL: sidecar image is '${c:-missing}'"

cmd=$(kubectl get deploy synergy-leverager -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].command}')
echo "$cmd" | grep -q "tail -n+1 -f /var/log/synergy-leverager.log" \
  && echo "PASS: sidecar command matches" || echo "FAIL: sidecar command is '$cmd'"

mnt=$(kubectl get deploy synergy-leverager -o jsonpath='{.spec.template.spec.containers[?(@.name=="synergy-leverager")].volumeMounts[?(@.mountPath=="/var/log")].name}')
[[ -n "$mnt" ]] && echo "PASS: original container has /var/log mounted" || echo "FAIL: original container missing /var/log mount"

ready=$(kubectl get deploy synergy-leverager -o jsonpath='{.status.readyReplicas}')
[[ "$ready" -ge 1 ]] 2>/dev/null && echo "PASS: Deployment has $ready ready replica(s)" || echo "FAIL: no ready replicas"

out=$(kubectl logs deploy/synergy-leverager -c sidecar --tail=3 2>/dev/null)
[[ -n "$out" ]] && echo "PASS: sidecar is streaming log lines" || echo "FAIL: no output from sidecar logs"

echo
echo "--- Task B: big-corp-app ---"
c=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="sidecar")].image}')
[[ "$c" == busybox* ]] && echo "PASS: sidecar image is $c" || echo "FAIL: sidecar image is '${c:-missing}'"

cmd=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="sidecar")].command}')
echo "$cmd" | grep -q "tail -n+1 -f /var/log/big-corp-app.log" \
  && echo "PASS: sidecar command matches" || echo "FAIL: sidecar command is '$cmd'"

mnt=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="big-corp-app")].volumeMounts[?(@.mountPath=="/var/log")].name}')
[[ -n "$mnt" ]] && echo "PASS: original container has /var/log mounted" || echo "FAIL: original container missing /var/log mount"

phase=$(kubectl get pod big-corp-app -o jsonpath='{.status.phase}')
[[ "$phase" == "Running" ]] && echo "PASS: Pod is Running" || echo "FAIL: Pod phase is $phase"

out=$(kubectl logs big-corp-app -c sidecar --tail=3 2>/dev/null)
[[ -n "$out" ]] && echo "PASS: sidecar is streaming log lines" || echo "FAIL: no output from sidecar logs"
