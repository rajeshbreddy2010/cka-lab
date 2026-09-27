## Solution
### Step 1: edit the ConfigMap
```bash
kubectl edit configmap nginx-config -n nginx-static
```
Change:
```
ssl_protocols       TLSv1.2 TLSv1.3;
```
to:
```
ssl_protocols       TLSv1.3;
```

Or non-interactively:
```bash
kubectl get cm nginx-config -n nginx-static -o yaml \
  | sed 's/ssl_protocols       TLSv1.2 TLSv1.3;/ssl_protocols       TLSv1.3;/' \
  | kubectl apply -f -
```

### Step 2: force nginx to pick up the change
```bash
kubectl rollout restart deployment nginx-static -n nginx-static
kubectl rollout status deployment nginx-static -n nginx-static
```

(Re-creating the Pod, e.g. `kubectl delete pod -n nginx-static -l
app=nginx-static`, works just as well — the task explicitly allows
re-creating, restarting, or scaling.)

### Step 3: verify
```bash
curl -k --tls-max 1.2 https://web.k8s.local
# should now FAIL: SSL routine failure / handshake failure / connection reset

curl -k --tlsv1.3 https://web.k8s.local
# should still SUCCEED: 200 ok
```

---
