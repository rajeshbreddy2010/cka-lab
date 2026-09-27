# Lab: Restrict NGINX to TLSv1.3 Only (namespace `nginx-static`)

## Scenario
An NGINX Deployment named `nginx-static` is running in the `nginx-static`
namespace. It is configured using a ConfigMap named `nginx-config`.

## Task
Update the `nginx-config` ConfigMap to allow only **TLSv1.3** connections.

You may re-create, restart, or scale resources as necessary.

You can use the following command to test the changes:

```bash
curl --tls-max 1.2 https://web.k8s.local
```

(After the fix, this command should **fail** to connect — it's forcing
TLS 1.2, which should now be rejected.)

---

## 0. Prerequisites

This needs a resolvable hostname pointing at the node running the Pod, and
port 443 reachable from wherever you run `curl`. The setup below uses
`hostNetwork: true` pinned to one node, plus a hosts-file entry, to keep
this runnable on a small kind/minikube/kubeadm cluster without needing a
real Ingress controller or LoadBalancer.

---

## 1. Setup (run as instructor / before the exercise)

```bash
#!/usr/bin/env bash
set -euo pipefail

NS=nginx-static
NODE=${1:-$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[*].effect}{"\n"}{end}' \
  | awk '!/NoSchedule/ {print $1; exit}')}
[[ -n "$NODE" ]] || { echo "No schedulable node found; pass one: bash setup.sh <node>"; exit 1; }

kubectl delete namespace "$NS" --ignore-not-found --wait=true
kubectl create namespace "$NS"

# --- self-signed cert for web.k8s.local ---
TMPDIR=$(mktemp -d)
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout "$TMPDIR/tls.key" -out "$TMPDIR/tls.crt" \
  -subj "/CN=web.k8s.local" -addext "subjectAltName=DNS:web.k8s.local" \
  >/dev/null 2>&1

kubectl create secret tls nginx-tls -n "$NS" \
  --cert="$TMPDIR/tls.crt" --key="$TMPDIR/tls.key"
rm -rf "$TMPDIR"

# --- ConfigMap: deliberately too permissive (TLSv1.2 AND TLSv1.3) ---
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx-static
data:
  default.conf: |
    server {
      listen 443 ssl;
      server_name web.k8s.local;

      ssl_certificate     /etc/nginx/certs/tls.crt;
      ssl_certificate_key /etc/nginx/certs/tls.key;
      ssl_protocols       TLSv1.2 TLSv1.3;

      location / {
        return 200 "ok\n";
      }
    }
EOF

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-static
  namespace: $NS
  labels:
    app: nginx-static
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-static
  template:
    metadata:
      labels:
        app: nginx-static
    spec:
      hostNetwork: true
      nodeSelector:
        kubernetes.io/hostname: $NODE
      containers:
      - name: nginx
        image: nginx:stable
        ports:
        - containerPort: 443
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: default.conf
        - name: certs
          mountPath: /etc/nginx/certs
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: nginx-config
      - name: certs
        secret:
          secretName: nginx-tls
EOF

kubectl rollout status deploy/nginx-static -n "$NS" --timeout=60s

NODE_IP=$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

echo
echo "Setup complete on node $NODE ($NODE_IP)."
echo "Add this to /etc/hosts on the machine you'll run curl from:"
echo "  $NODE_IP  web.k8s.local"
echo
echo "Then confirm the (currently too permissive) starting state:"
echo "  curl -k --tls-max 1.2 https://web.k8s.local   # should succeed (200 ok) -- this is the bug"
echo "  curl -k --tlsv1.3    https://web.k8s.local    # should also succeed"
```

Add the hosts entry it prints, e.g.:

```bash
echo "$(kubectl get node <node> -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')  web.k8s.local" \
  | sudo tee -a /etc/hosts
```

**Expected starting (broken) state**

```bash
curl -k --tls-max 1.2 https://web.k8s.local
# HTTP/1.1 200 -- succeeds because TLSv1.2 is still allowed (this is the bug to fix)
```

---

## 2. Hints (reveal one at a time)

1. `kubectl get cm nginx-config -n nginx-static -o yaml` shows the current
   `ssl_protocols` line inside the embedded `nginx.conf`.
2. Only remove `TLSv1.2` from `ssl_protocols` — don't touch the certificate
   or key lines, or the server won't start at all.
3. Editing a ConfigMap does **not** automatically make a running container
   re-read it. Kubernetes eventually syncs the mounted file on the node
   (after some delay, via kubelet's periodic sync), but nginx itself won't
   reload its config just because the file on disk changed — you still need
   to reload/restart the nginx process, most simply by restarting the Pod.
4. `kubectl rollout restart deployment nginx-static -n nginx-static` is the
   cleanest way to force new Pods (and thus a fresh nginx process) after
   editing the ConfigMap.
5. Since the Pod uses `hostNetwork: true` and is pinned to one node,
   restarting the Deployment doesn't move it elsewhere — the same node/IP
   still serves `web.k8s.local` after the restart.
6. If `curl` hangs or resets instead of giving a clean TLS error, that's
   still a pass — it means the handshake was rejected, which is the point.

---

## 3. Solution

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

## 4. Verification / checker

Save as `check.sh`:

```bash
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
```

Success criteria:

- `nginx-config`'s `ssl_protocols` line contains only `TLSv1.3`.
- The nginx Pod has been restarted/recreated since the edit (config on disk
  and the running process actually match).
- `curl --tls-max 1.2 https://web.k8s.local` fails.
- A TLS 1.3 request to the same host still succeeds.

---

## 5. Cleanup
```bash
kubectl delete namespace nginx-static
sudo sed -i '/web\.k8s\.local/d' /etc/hosts
```

## 6. Optional extensions

- Also restrict `ssl_ciphers` to a TLS 1.3-appropriate cipher suite and
  discuss why `ssl_ciphers` is mostly meaningless once only TLS 1.3 is
  allowed (TLS 1.3 uses its own fixed, modern cipher suite list).
- Add a `livenessProbe`/`readinessProbe` using HTTPS with `--tlsv1.3` so a
  misconfigured (e.g. syntax-broken) reload is caught automatically instead
  of silently leaving stale Pods serving traffic.
- Replace `hostNetwork` + hosts-file with a proper Ingress controller doing
  TLS passthrough, and compare the operational trade-offs.
- Intentionally break the `nginx.conf` syntax in the ConfigMap (e.g. a
  missing semicolon) and practice diagnosing why new Pods now
  `CrashLoopBackOff` after a rollout restart.
