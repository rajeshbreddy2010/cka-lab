#!/usr/bin/env bash
NS=nginx-static

conf=$(kubectl get cm nginx-config -n $NS -o jsonpath='{.data.default\.conf}')
echo "$conf" | grep -q 'ssl_protocols[[:space:]]*TLSv1\.3;' \
  && echo "PASS: ConfigMap allows only TLSv1.3" \
  || echo "FAIL: ssl_protocols line is: $(echo "$conf" | grep ssl_protocols)"

echo "$conf" | grep 'ssl_protocols' | grep -q 'TLSv1\.2' \
  && echo "FAIL: TLSv1.2 is still listed in ssl_protocols" \
  || echo "PASS: TLSv1.2 is not listed"

ready=$(kubectl get deploy nginx-static -n $NS -o jsonpath='{.status.readyReplicas}')
[[ "$ready" -ge 1 ]] 2>/dev/null && echo "PASS: nginx-static Deployment is ready" \
  || echo "FAIL: nginx-static Deployment not ready"

echo
echo "Live TLS checks (requires web.k8s.local resolvable and reachable):"
if curl -sk --tls-max 1.2 -o /dev/null https://web.k8s.local 2>/dev/null; then
  echo "FAIL: TLSv1.2 connection succeeded -- it should be rejected"
else
  echo "PASS: TLSv1.2 connection was rejected"
fi

if curl -sk --tlsv1.3 -o /dev/null https://web.k8s.local 2>/dev/null; then
  echo "PASS: TLSv1.3 connection succeeded"
else
  echo "FAIL: TLSv1.3 connection failed -- something else is wrong (cert, config syntax, Pod not restarted)"
fi
