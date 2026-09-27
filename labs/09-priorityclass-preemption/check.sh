#!/usr/bin/env bash
NS=priority

# highest user-defined value, ignoring system classes and high-priority itself
top=$(kubectl get pc -o jsonpath='{range .items[*]}{.metadata.name} {.value}{"\n"}{end}' \
  | grep -v '^system-' | grep -v '^high-priority ' | sort -k2 -n | tail -1 | awk '{print $2}')
expected=$((top - 1))
actual=$(kubectl get pc high-priority -o jsonpath='{.value}' 2>/dev/null)
[[ "$actual" == "$expected" ]] \
  && echo "PASS: high-priority value is $actual (highest user value $top - 1)" \
  || echo "FAIL: high-priority value is '${actual:-missing}', expected $expected"

pc=$(kubectl get deploy busybox-logger -n $NS -o jsonpath='{.spec.template.spec.priorityClassName}')
[[ "$pc" == "high-priority" ]] && echo "PASS: busybox-logger uses high-priority" \
  || echo "FAIL: busybox-logger priorityClassName is '${pc:-unset}'"

ready=$(kubectl get deploy busybox-logger -n $NS -o jsonpath='{.status.readyReplicas}')
[[ "$ready" == "3" ]] && echo "PASS: busybox-logger 3/3 ready" \
  || echo "FAIL: busybox-logger ready replicas = ${ready:-0}"

# other deployments must be untouched (generation 1, replicas 2, no priority class)
for d in web-frontend batch-worker; do
  gen=$(kubectl get deploy $d -n $NS -o jsonpath='{.metadata.generation}')
  rep=$(kubectl get deploy $d -n $NS -o jsonpath='{.spec.replicas}')
  dpc=$(kubectl get deploy $d -n $NS -o jsonpath='{.spec.template.spec.priorityClassName}')
  [[ "$gen" == "1" && "$rep" == "2" && -z "$dpc" ]] \
    && echo "PASS: $d was not modified" \
    || echo "FAIL: $d was modified (generation=$gen replicas=$rep priorityClass='$dpc')"
done

echo
echo "Other Pods (some should now be Pending/evicted):"
kubectl get pods -n $NS
