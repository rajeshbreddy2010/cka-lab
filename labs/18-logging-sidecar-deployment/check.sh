#!/usr/bin/env bash
pass(){ echo "PASS: $1"; }; fail(){ echo "FAIL: $1"; }
NS=default
DEPLOY=synergy-leverager

kubectl -n $NS get deploy $DEPLOY >/dev/null 2>&1 || { fail "Deployment $DEPLOY not found"; exit 1; }

NAMES=$(kubectl -n $NS get deploy $DEPLOY -o jsonpath='{.spec.template.spec.containers[*].name}')
[[ "$NAMES" == *sidecar* ]] && pass "container 'sidecar' exists" || fail "no container named 'sidecar'"
[[ "$NAMES" == *synergy-leverager* ]] && pass "original container still present" || fail "original container missing/renamed"

SIDECAR_IMG=$(kubectl -n $NS get deploy $DEPLOY -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].image}')
[[ "$SIDECAR_IMG" == busybox:stable ]] && pass "sidecar image is busybox:stable" || fail "sidecar image is '$SIDECAR_IMG', expected busybox:stable"

SIDECAR_CMD=$(kubectl -n $NS get deploy $DEPLOY -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].command}')
[[ "$SIDECAR_CMD" == *"tail"* && "$SIDECAR_CMD" == *"synergy-leverager.log"* ]] \
  && pass "sidecar command tails synergy-leverager.log" || fail "sidecar command wrong: $SIDECAR_CMD"

MAIN_CMD=$(kubectl -n $NS get deploy $DEPLOY -o jsonpath='{.spec.template.spec.containers[?(@.name=="synergy-leverager")].command}')
[[ "$MAIN_CMD" == *"synergy-leverager.log"* ]] \
  && pass "existing container's command is unmodified" || fail "existing container's command/args look changed: $MAIN_CMD"

MAIN_MOUNT=$(kubectl -n $NS get deploy $DEPLOY -o jsonpath='{.spec.template.spec.containers[?(@.name=="synergy-leverager")].volumeMounts[?(@.mountPath=="/var/log")].name}')
SIDE_MOUNT=$(kubectl -n $NS get deploy $DEPLOY -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].volumeMounts[?(@.mountPath=="/var/log")].name}')
[[ -n "$MAIN_MOUNT" ]] && pass "existing container mounts a volume at /var/log ($MAIN_MOUNT)" || fail "existing container has no volume mounted at /var/log"
[[ -n "$SIDE_MOUNT" ]] && pass "sidecar mounts a volume at /var/log ($SIDE_MOUNT)" || fail "sidecar has no volume mounted at /var/log"
[[ -n "$MAIN_MOUNT" && "$MAIN_MOUNT" == "$SIDE_MOUNT" ]] \
  && pass "both containers share the SAME volume ($MAIN_MOUNT)" || fail "containers mount different volumes - log won't be shared"

kubectl -n $NS rollout status deploy/$DEPLOY --timeout=60s >/dev/null 2>&1 \
  && pass "rollout is healthy" || fail "rollout did not complete"

POD=$(kubectl -n $NS get pod -l app=synergy-leverager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
sleep 6
if [[ -n "$POD" ]] && kubectl -n $NS logs "$POD" -c sidecar --tail=5 2>/dev/null | grep -q 'synergy-leverager running'; then
  pass "sidecar is streaming real log lines"
else
  fail "sidecar produced no matching log lines (check the shared volume/mountPath)"
fi
