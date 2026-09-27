#!/usr/bin/env bash

echo "--- cert-manager health ---"
for d in cert-manager cert-manager-webhook cert-manager-cainjector; do
  ready=$(kubectl get deploy "$d" -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  desired=$(kubectl get deploy "$d" -n cert-manager -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" == "$desired" ]] \
    && echo "PASS: $d is healthy ($ready/$desired ready)" \
    || echo "FAIL: $d is not healthy (ready=${ready:-0}/$desired)"
done

echo
echo "--- resources.yaml ---"
if [[ -s ~/resources.yaml ]]; then
  n=$(grep -c "cert-manager.io" ~/resources.yaml)
  [[ "$n" -ge 6 ]] && echo "PASS: lists $n cert-manager CRDs" \
    || echo "FAIL: lists only $n (expected 6)"
  head -1 ~/resources.yaml | grep -qi '^NAME' \
    && echo "PASS: looks like default table output (has a NAME header)" \
    || echo "WARN: no NAME header found -- confirm no -o flag was used"
else
  echo "FAIL: ~/resources.yaml missing or empty"
fi

echo
echo "--- subject.yaml ---"
if [[ -s ~/subject.yaml ]]; then
  grep -qi "^FIELD:" ~/subject.yaml && grep -qi "subject" ~/subject.yaml \
    && echo "PASS: looks like 'kubectl explain certificate.spec.subject' output" \
    || echo "FAIL: content doesn't look like kubectl explain output"
else
  echo "FAIL: ~/subject.yaml missing or empty"
fi
