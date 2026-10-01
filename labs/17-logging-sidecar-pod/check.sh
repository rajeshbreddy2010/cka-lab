#!/usr/bin/env bash
pass(){ echo "PASS: $1"; }; fail(){ echo "FAIL: $1"; }
g(){ kubectl get pod big-corp-app -o jsonpath="$1" 2>/dev/null; }

kubectl get pod big-corp-app >/dev/null 2>&1 || { fail "Pod big-corp-app not found"; exit 1; }

NAMES=$(g '{.spec.containers[*].name}')
[[ "$NAMES" == *sidecar* ]] && pass "container 'sidecar' exists" || fail "no container named 'sidecar'"
[[ "$NAMES" == *big-corp-app* ]] && pass "original container 'big-corp-app' still present" || fail "original container missing"

SIDECAR_IMG=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="sidecar")].image}')
[[ "$SIDECAR_IMG" == busybox* ]] && pass "sidecar image is busybox ($SIDECAR_IMG)" || fail "sidecar image is '$SIDECAR_IMG', expected busybox"

SIDECAR_CMD=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="sidecar")].command}')
[[ "$SIDECAR_CMD" == *"tail"* && "$SIDECAR_CMD" == *"big-corp-app.log"* ]] \
  && pass "sidecar command tails big-corp-app.log" || fail "sidecar command wrong: $SIDECAR_CMD"

MAIN_MOUNT=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="big-corp-app")].volumeMounts[?(@.mountPath=="/var/log")].name}')
SIDE_MOUNT=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="sidecar")].volumeMounts[?(@.mountPath=="/var/log")].name}')
[[ -n "$MAIN_MOUNT" ]] && pass "main container mounts a volume at /var/log ($MAIN_MOUNT)" || fail "main container has no volume mounted at /var/log"
[[ -n "$SIDE_MOUNT" ]] && pass "sidecar mounts a volume at /var/log ($SIDE_MOUNT)" || fail "sidecar has no volume mounted at /var/log"
[[ -n "$MAIN_MOUNT" && "$MAIN_MOUNT" == "$SIDE_MOUNT" ]] \
  && pass "both containers share the SAME volume ($MAIN_MOUNT)" || fail "containers mount different volumes - log won't be shared"

PHASE=$(g '{.status.phase}')
[[ "$PHASE" == "Running" ]] && pass "Pod is Running" || fail "Pod phase is $PHASE"

# Actually prove the log is flowing end-to-end
sleep 6
if kubectl logs big-corp-app -c sidecar --tail=5 2>/dev/null | grep -q 'big-corp-app running'; then
  pass "sidecar is streaming real log lines"
else
  fail "sidecar produced no matching log lines (check the shared volume/mountPath)"
fi
