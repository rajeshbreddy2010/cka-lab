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
