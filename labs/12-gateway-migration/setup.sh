#!/usr/bin/env bash
# Builds the starting state:
#   - Envoy Gateway (Gateway API CRDs + controller) and a GatewayClass "eg"
#   - TLS Secret web-tls, two backends, and the existing Ingress "web" (default namespace)
# It does NOT create the Gateway or HTTPRoute - that is your task.
set -euo pipefail
cd "$(dirname "$0")"

EG_VERSION=v1.7.0

if ! kubectl -n envoy-gateway-system get deploy envoy-gateway >/dev/null 2>&1; then
  echo "Installing Envoy Gateway $EG_VERSION (Gateway API CRDs + controller)..."
  # server-side apply: the CRDs are too large for client-side apply annotations
  kubectl apply --server-side --force-conflicts \
    -f "https://github.com/envoyproxy/gateway/releases/download/${EG_VERSION}/install.yaml"
fi
kubectl -n envoy-gateway-system wait --timeout=5m deploy/envoy-gateway --for=condition=Available

kubectl apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
YAML

# Clean any previous attempt
kubectl delete gateway web-gateway --ignore-not-found
kubectl delete httproute web-route --ignore-not-found

# Self-signed cert for the Ingress/Gateway hostname
TMP=$(mktemp -d)
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout "$TMP/tls.key" -out "$TMP/tls.crt" \
  -subj "/CN=gateway.web.k8s.local" \
  -addext "subjectAltName=DNS:gateway.web.k8s.local" 2>/dev/null
kubectl create secret tls web-tls --cert="$TMP/tls.crt" --key="$TMP/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -rf "$TMP"

kubectl apply -f manifests.yaml
kubectl rollout status deploy/web --timeout=120s
kubectl rollout status deploy/api --timeout=120s

echo
kubectl get gatewayclass
echo
echo "Lab ready. Existing Ingress:"
kubectl get ingress web
echo
echo "Your task: see TASK.md. Migrate Ingress 'web' to Gateway 'web-gateway' + HTTPRoute 'web-route', then delete the Ingress."
