#!/usr/bin/env bash
NS=echo-sound
pass(){ echo "PASS: $1"; }; fail(){ echo "FAIL: $1"; }

[[ "$(kubectl -n $NS get svc echo-service -o jsonpath='{.spec.type}' 2>/dev/null)" == "NodePort" ]] \
  && pass "Service echo-service is NodePort" || fail "Service echo-service missing or not NodePort"
[[ "$(kubectl -n $NS get svc echo-service -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" == "8080" ]] \
  && pass "Service port is 8080" || fail "Service port is not 8080"
[[ -n "$(kubectl -n $NS get endpoints echo-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)" ]] \
  && pass "Service has endpoints" || fail "Service has no endpoints (selector wrong?)"
[[ "$(kubectl -n $NS get ingress echo -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)" == "example.org" ]] \
  && pass "Ingress echo host is example.org" || fail "Ingress echo missing or wrong host"
[[ "$(kubectl -n $NS get ingress echo -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)" == "/echo" ]] \
  && pass "Ingress path is /echo" || fail "Ingress path is not /echo"

CODE=$(curl -o /dev/null -s -w "%{http_code}\n" http://example.org/echo)
[[ "$CODE" == "200" ]] && pass "curl returned 200" || fail "curl returned $CODE (ingress may need a few seconds)"
