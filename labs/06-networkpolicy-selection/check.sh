#!/usr/bin/env bash

count=$(kubectl get networkpolicy -n backend --no-headers 2>/dev/null | wc -l)
[[ "$count" == "1" ]] && echo "PASS: exactly one NetworkPolicy applied in backend" \
  || echo "FAIL: $count NetworkPolicies found in backend (expected exactly 1)"

name=$(kubectl get networkpolicy -n backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[[ "$name" == "allow-frontend-to-backend" ]] \
  && echo "PASS: the correct policy (allow-frontend-to-backend) is applied" \
  || echo "FAIL: applied policy is '${name:-none}', expected allow-frontend-to-backend"

# Make sure ingress isn't allowed from everywhere (i.e. no empty 'from')
empty_from=$(kubectl get networkpolicy "$name" -n backend -o jsonpath='{.spec.ingress[0].from}' 2>/dev/null)
[[ "$empty_from" != "[{}]" && -n "$empty_from" ]] \
  && echo "PASS: ingress is scoped (not an open 'allow from anywhere' rule)" \
  || echo "FAIL: ingress rule looks unscoped -- check for overly permissive 'from: [{}]'"

# Sample files must be untouched
missing=0
for f in 01-deny-all 02-allow-all-ingress 03-allow-frontend-wrong-port 04-allow-wrong-pod-selector 05-allow-frontend-to-backend; do
  [[ -f ~/netpol/$f.yaml ]] || { echo "FAIL: ~/netpol/$f.yaml is missing"; missing=1; }
done
[[ "$missing" == "0" ]] && echo "PASS: all sample files are still present in ~/netpol"

echo
echo "Connectivity checks:"
kubectl exec -n frontend deploy/frontend -- curl -s -m3 backend.backend.svc.cluster.local:8080 \
  && echo "PASS: frontend can reach backend" || echo "FAIL: frontend cannot reach backend"
kubectl exec -n other deploy/prober -- curl -s -m3 backend.backend.svc.cluster.local:8080 \
  && echo "FAIL: unrelated namespace 'other' can also reach backend -- too permissive" \
  || echo "PASS: unrelated namespace 'other' is correctly blocked"
