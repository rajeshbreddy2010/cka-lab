#!/usr/bin/env bash
kubectl config use-context kind-cni-lab >/dev/null 2>&1 || true
pass(){ echo "PASS: $1"; }; fail(){ echo "FAIL: $1"; }

kubectl get nodes | grep -q ' Ready' \
  && pass "nodes are Ready (CNI installed)" || fail "nodes not Ready - CNI missing or not up yet"

kubectl -n calico-system get pods >/dev/null 2>&1 \
  && pass "calico-system namespace exists" || fail "calico-system not found - did you install Calico?"

NOTREADY=$(kubectl -n calico-system get pods --no-headers 2>/dev/null | grep -v 'Running\|Completed' | wc -l)
[[ "$NOTREADY" == "0" ]] \
  && pass "all calico-system pods are Running" || fail "$NOTREADY calico-system pod(s) not Running yet"

# NetworkPolicy enforcement test
kubectl create ns netpol-check --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n netpol-check run web --image=nginx:alpine --port=80 --expose >/dev/null 2>&1 || true
kubectl -n netpol-check run client --image=busybox:1.36 --restart=Never -- sleep 3600 >/dev/null 2>&1 || true
kubectl -n netpol-check wait --for=condition=Ready pod/web pod/client --timeout=60s >/dev/null 2>&1

kubectl apply -f - <<'YAML' >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: netpol-check
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
YAML
sleep 3
if kubectl -n netpol-check exec client -- wget -qO- --timeout=5 http://web >/dev/null 2>&1; then
  fail "NetworkPolicy NOT enforced (traffic still allowed) - Flannel doesn't support this, use Calico"
else
  pass "NetworkPolicy IS enforced (traffic correctly blocked)"
fi
kubectl delete ns netpol-check --ignore-not-found >/dev/null 2>&1
