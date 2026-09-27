#!/usr/bin/env bash
set -euo pipefail

# ---------- Task A: Deployment synergy-leverager ----------
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: synergy-leverager
  labels:
    app: synergy-leverager
spec:
  replicas: 1
  selector:
    matchLabels:
      app: synergy-leverager
  template:
    metadata:
      labels:
        app: synergy-leverager
    spec:
      containers:
      - name: synergy-leverager
        image: busybox:stable
        command: ["/bin/sh", "-c"]
        args:
          - >
            i=0;
            while true; do
              echo "$(date -u +%FT%TZ) line $i: synergy-leverager running" >> /var/log/synergy-leverager.log;
              i=$((i+1));
              sleep 5;
            done
EOF

kubectl rollout status deploy/synergy-leverager --timeout=60s

# ---------- Task B: bare Pod big-corp-app ----------
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: big-corp-app
  labels:
    app: big-corp-app
spec:
  containers:
  - name: big-corp-app
    image: busybox:stable
    command: ["/bin/sh", "-c"]
    args:
      - >
        i=0;
        while true; do
          echo "$(date -u +%FT%TZ) line $i: big-corp-app running" >> /var/log/big-corp-app.log;
          i=$((i+1));
          sleep 5;
        done
EOF

kubectl wait --for=condition=Ready pod/big-corp-app --timeout=60s

echo
echo "Setup complete."
echo "  kubectl exec deploy/synergy-leverager -- cat /var/log/synergy-leverager.log"
echo "  kubectl exec big-corp-app -- cat /var/log/big-corp-app.log"
echo "Neither log is visible via 'kubectl logs' yet — that's the task."
