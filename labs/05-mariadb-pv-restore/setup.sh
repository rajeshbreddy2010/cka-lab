#!/usr/bin/env bash
set -euo pipefail

NS=mariadb
NODE=${1:-$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[*].effect}{"\n"}{end}' \
  | awk '!/NoSchedule/ {print $1; exit}')}
[[ -n "$NODE" ]] || { echo "No schedulable node found; pass one: bash setup.sh <node>"; exit 1; }

kubectl delete namespace "$NS" --ignore-not-found --wait=true
kubectl delete pv mariadb-pv --ignore-not-found

kubectl create namespace "$NS"

# Host directory for the hostPath PV
kubectl debug node/"$NODE" -it --image=busybox:stable -- \
  sh -c "mkdir -p /host/mnt/mariadb-pv-data && chmod 777 /host/mnt/mariadb-pv-data" >/dev/null 2>&1 || \
  echo "Note: could not pre-create host dir remotely; hostPath will create it on first mount."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv
  labels:
    type: mariadb-data
spec:
  capacity:
    storage: 250Mi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/mariadb-pv-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $NODE
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-original
  namespace: $NS
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 250Mi
EOF

kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/mariadb-original -n "$NS" --timeout=30s

# Write a marker file to prove data persistence later
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: seed-writer
  namespace: $NS
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: $NODE
  containers:
  - name: writer
    image: busybox:stable
    command: ["/bin/sh", "-c"]
    args:
      - echo "restored-mariadb-data-$(date -u +%FT%TZ)" > /var/lib/mysql/RESTORE_MARKER; sleep 2
    volumeMounts:
    - name: data
      mountPath: /var/lib/mysql
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: mariadb-original
EOF

kubectl wait --for=condition=Ready pod/seed-writer -n "$NS" --timeout=30s || true
sleep 3
kubectl delete pod seed-writer -n "$NS" --wait=true

# --- simulate "deleted by mistake" ---
kubectl delete pvc mariadb-original -n "$NS" --wait=true

echo "PV after the accident (Released, stale claimRef):"
kubectl get pv mariadb-pv

# Deployment file the candidate has to edit
cat <<EOF > ~/mariadb-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: $NS
  labels:
    app: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.11
        env:
        - name: MARIADB_ROOT_PASSWORD
          value: changeme
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
      # volumes: <- candidate must add this, pointing at the PVC
EOF

echo
echo "Setup complete."
echo "  PV mariadb-pv exists, Released, data retained on node $NODE."
echo "  ~/mariadb-deployment.yaml is ready to edit."
echo "  kubectl get pv mariadb-pv"
echo "  kubectl get pvc -n $NS      # should show none"
echo "  kubectl get deploy -n $NS   # should show none"
