#!/usr/bin/env bash
pass(){ echo "PASS: $1"; }; fail(){ echo "FAIL: $1"; }
cd "$(dirname "$0")"

[[ "$(kubectl get sc local-storage -o jsonpath='{.provisioner}' 2>/dev/null)" == "rancher.io/local-path" ]] \
  && pass "provisioner is rancher.io/local-path" || fail "local-storage missing or wrong provisioner"
[[ "$(kubectl get sc local-storage -o jsonpath='{.volumeBindingMode}' 2>/dev/null)" == "WaitForFirstConsumer" ]] \
  && pass "volumeBindingMode is WaitForFirstConsumer" || fail "volumeBindingMode wrong"

DEFAULTS=$(kubectl get sc -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)["items"]
print(" ".join(i["metadata"]["name"] for i in d if i["metadata"].get("annotations",{}).get("storageclass.kubernetes.io/is-default-class")=="true"))')
[[ "$DEFAULTS" == "local-storage" ]] \
  && pass "local-storage is the only default" || fail "default classes: [$DEFAULTS]"

if [[ -f .baseline ]]; then
  source .baseline
  [[ "$(kubectl -n storage-lab get deploy data-app -o jsonpath='{.metadata.generation}')" == "$DEPLOY_GEN" ]] \
    && pass "Deployment data-app unmodified" || fail "Deployment data-app was modified"
  [[ "$(kubectl -n storage-lab get pvc data-pvc -o jsonpath='{.metadata.uid}')" == "$PVC_UID" && \
     "$(kubectl -n storage-lab get pvc data-pvc -o jsonpath='{.spec.storageClassName}')" == "$PVC_SC" ]] \
    && pass "PVC data-pvc unmodified" || fail "PVC data-pvc was modified/recreated"
fi
