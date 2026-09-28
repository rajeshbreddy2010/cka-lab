#!/usr/bin/env bash
pass(){ echo "PASS: $1"; }; fail(){ echo "FAIL: $1"; }
g(){ kubectl get gateway web-gateway -o jsonpath="$1" 2>/dev/null; }
r(){ kubectl get httproute web-route -o jsonpath="$1" 2>/dev/null; }

# --- Gateway ---
[[ -n "$(g '{.metadata.name}')" ]] && pass "Gateway web-gateway exists" || fail "Gateway web-gateway not found"
[[ -n "$(g '{.spec.gatewayClassName}')" ]] && pass "gatewayClassName set ($(g '{.spec.gatewayClassName}'))" || fail "gatewayClassName missing"
[[ "$(g '{.spec.listeners[0].hostname}')" == "gateway.web.k8s.local" ]] \
  && pass "listener hostname gateway.web.k8s.local" || fail "listener hostname wrong"
[[ "$(g '{.spec.listeners[0].protocol}')" == "HTTPS" && "$(g '{.spec.listeners[0].port}')" == "443" ]] \
  && pass "listener is HTTPS on 443" || fail "listener should be HTTPS on port 443"
[[ "$(g '{.spec.listeners[0].tls.certificateRefs[0].name}')" == "web-tls" ]] \
  && pass "TLS certificateRef is web-tls" || fail "TLS certificateRef should be Secret web-tls"
[[ "$(g '{.status.conditions[?(@.type=="Accepted")].status}')" == "True" ]] \
  && pass "Gateway Accepted by controller" || fail "Gateway not Accepted (kubectl describe gateway web-gateway)"

# --- HTTPRoute ---
[[ -n "$(r '{.metadata.name}')" ]] && pass "HTTPRoute web-route exists" || fail "HTTPRoute web-route not found"
[[ "$(r '{.spec.hostnames[0]}')" == "gateway.web.k8s.local" ]] \
  && pass "route hostname gateway.web.k8s.local" || fail "route hostname wrong"
[[ "$(r '{.spec.parentRefs[0].name}')" == "web-gateway" ]] \
  && pass "route attached to web-gateway" || fail "parentRefs should reference web-gateway"
BACKENDS=$(r '{range .spec.rules[*]}{.backendRefs[0].name}:{.backendRefs[0].port}{"\n"}{end}')
grep -q '^web-service:80$'  <<<"$BACKENDS" && pass "rule -> web-service:80"  || fail "missing rule to web-service:80"
grep -q '^api-service:8080$' <<<"$BACKENDS" && pass "rule -> api-service:8080" || fail "missing rule to api-service:8080"
[[ "$(r '{.status.parents[0].conditions[?(@.type=="Accepted")].status}')" == "True" ]] \
  && pass "HTTPRoute Accepted" || fail "HTTPRoute not Accepted"
[[ "$(r '{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}')" == "True" ]] \
  && pass "HTTPRoute backends resolved" || fail "HTTPRoute ResolvedRefs not True (wrong service name/port/namespace?)"

# --- Ingress deleted ---
kubectl get ingress web >/dev/null 2>&1 \
  && fail "Ingress web still exists (delete it last)" || pass "Ingress web deleted"

# --- Live traffic (via the Envoy Service NodePort, since bare metal has no LoadBalancer) ---
SVC=$(kubectl -n envoy-gateway-system get svc \
  -l gateway.envoyproxy.io/owning-gateway-name=web-gateway,gateway.envoyproxy.io/owning-gateway-namespace=default \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$SVC" ]]; then
  PORT=$(kubectl -n envoy-gateway-system get svc "$SVC" -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  H=gateway.web.k8s.local
  CODE=$(curl -sk --max-time 8 -o /dev/null -w '%{http_code}' --resolve $H:$PORT:$NODE_IP https://$H:$PORT/)
  [[ "$CODE" == "200" ]] && pass "https://$H/ returned 200" || fail "https://$H/ returned $CODE (proxy pod may still be starting)"
  curl -sk --max-time 8 --resolve $H:$PORT:$NODE_IP https://$H:$PORT/api | grep -q 'api' \
    && pass "/api routed to api-service" || fail "/api did not reach api-service"
else
  fail "no Envoy proxy Service found for web-gateway yet (Gateway not created or not programmed)"
fi
