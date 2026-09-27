#!/usr/bin/env bash
NS=mariadb

phase=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$phase" == "Bound" ]] && echo "PASS: PVC mariadb is Bound" || echo "FAIL: PVC phase is '${phase:-missing}'"

vol=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.spec.volumeName}' 2>/dev/null)
[[ "$vol" == "mariadb-pv" ]] && echo "PASS: PVC is bound to the existing PV mariadb-pv" \
  || echo "FAIL: PVC bound to '${vol:-nothing}' instead of mariadb-pv"

am=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.spec.accessModes[0]}')
[[ "$am" == "ReadWriteOnce" ]] && echo "PASS: accessMode is ReadWriteOnce" || echo "FAIL: accessMode is '$am'"

sz=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.spec.resources.requests.storage}')
[[ "$sz" == "250Mi" ]] && echo "PASS: storage request is 250Mi" || echo "FAIL: storage request is '$sz'"

claim=$(kubectl get deploy mariadb -n $NS -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null)
[[ "$claim" == "mariadb" ]] && echo "PASS: Deployment volume references PVC 'mariadb'" \
  || echo "FAIL: Deployment references claim '${claim:-none}'"

ready=$(kubectl get deploy mariadb -n $NS -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ "$ready" -ge 1 ]] 2>/dev/null && echo "PASS: mariadb Deployment has $ready ready replica(s)" \
  || echo "FAIL: mariadb Deployment not ready"

marker=$(kubectl exec -n $NS deploy/mariadb -- cat /var/lib/mysql/RESTORE_MARKER 2>/dev/null)
[[ "$marker" == restored-mariadb-data-* ]] && echo "PASS: original data is present ($marker)" \
  || echo "FAIL: RESTORE_MARKER missing — Deployment may be using a different/new volume"
