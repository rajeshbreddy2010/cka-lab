# Lab: Restore a deleted MariaDB Deployment with an existing PersistentVolume
(namespace `mariadb`)

## Scenario
A MariaDB Deployment in the `mariadb` namespace was deleted by mistake. The
underlying storage was provisioned with `reclaimPolicy: Retain`, so the data
still exists on a **PersistentVolume**, but the PersistentVolumeClaim and
Deployment are gone.

## Task
Restore the Deployment, ensuring data persistence:

1. Create a PersistentVolumeClaim named `mariadb` in the `mariadb` namespace:
   - Access mode `ReadWriteOnce`
   - Storage `250Mi`
   - **You must use the existing retained PersistentVolume.** Failure to do
     so will result in a reduced score. There is only one existing PV.
2. Edit the MariaDB Deployment file at `~/mariadb-deployment.yaml` to use the
   PVC you created, then apply it to the cluster.
3. Ensure the MariaDB Deployment is running and stable.

---

## 1. Setup (run as instructor / before the exercise)

This recreates the "accident": it provisions a PV, binds it, writes a marker
file to prove persistence, then deletes the Deployment and PVC — leaving the
PV **Released**, still holding the data, with a stale `claimRef` from the
deleted PVC. That stale `claimRef` is the trap: a fresh PVC that otherwise
matches perfectly will still sit `Pending` until the `claimRef` is cleared.

Uses `hostPath`, so it needs a node to pin the Pod and PV to. Works on a
single-node cluster automatically; on multi-node, pass the node name.

```bash
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
```

**Expected starting state**

```bash
kubectl get pv mariadb-pv
# STATUS = Released, CLAIM = mariadb/mariadb-original (a PVC that no longer exists)

kubectl get pvc -n mariadb
# No resources found

kubectl get deploy -n mariadb
# No resources found

cat ~/mariadb-deployment.yaml
# Deployment with no 'volumes:' section
```

---

## 2. Hints (reveal one at a time)

1. `kubectl get pv mariadb-pv -o yaml` shows `status.phase: Released` and a
   `spec.claimRef` still pointing at the old, now-deleted PVC.
2. A `Released` PV is **not** automatically reusable. A brand-new PVC that
   matches capacity/accessMode/storageClassName perfectly will still stay
   `Pending` if the PV's `claimRef` points somewhere else (or to something
   that no longer exists) — the claimRef is checked, not just the specs.
3. To make the PV `Available` again for a new claim, remove its `claimRef`:
   `kubectl patch pv mariadb-pv -p '{"spec":{"claimRef": null}}'`, or edit /
   `replace` the PV's YAML with the `claimRef:` block deleted. Note that
   `kubectl apply` alone won't clear it — `apply` only touches fields it
   previously managed, and `claimRef` was set by the binding controller.
4. The PVC must request the same `storageClassName` as the PV (`manual`
   here) — a PVC with no storage class, or a different one, may bind to a
   different (or no) PV depending on your default StorageClass.
5. To pin the new PVC to *this specific* PV, either clear the claimRef and
   let matching specs bind them, or set `spec.volumeName: mariadb-pv`
   explicitly on the PVC to force it.
6. `250Mi` in the PVC must be `<=` the PV's capacity (`250Mi`) — requesting
   more than the PV offers will leave the PVC unbound forever, since there's
   only one PV to bind against.
7. The Deployment file has a `volumeMounts` entry named `data` but no
   `volumes:` section yet — add it under `spec.template.spec.volumes`,
   referencing your new PVC by name (`mariadb`).

---

## 3. Solution

### Step 1: make the PV available again
```bash
kubectl get pv mariadb-pv -o yaml | grep -A5 claimRef
kubectl patch pv mariadb-pv --type=merge -p '{"spec":{"claimRef": null}}'
kubectl get pv mariadb-pv
# STATUS should now be Available
```

**Declarative (YAML file) alternative.** `kubectl apply` will **not** clear
`claimRef` here — `apply` only touches fields it previously set, and
`claimRef` was set by the binding controller, not by an earlier `apply`. Use
`kubectl replace` instead, which fully overwrites the spec:

```bash
kubectl get pv mariadb-pv -o yaml > mariadb-pv.yaml
```

Edit `mariadb-pv.yaml`: delete the entire `claimRef:` block under `spec:`,
and strip `resourceVersion`, `uid`, and the `status:` section (leave the rest
of `spec` — capacity, accessModes, hostPath, nodeAffinity, etc. — untouched).
Then:

```bash
kubectl replace -f mariadb-pv.yaml
kubectl get pv mariadb-pv
# STATUS should now be Available
```

`kubectl edit pv mariadb-pv` (delete the `claimRef:` block and save) works
the same way, since `edit` applies a full-object diff like `replace`.

### Step 2: create the PVC
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 250Mi
```
```bash
kubectl apply -f mariadb-pvc.yaml
kubectl get pvc mariadb -n mariadb
# STATUS = Bound, VOLUME = mariadb-pv
```
If it doesn't bind, double check `storageClassName: manual` matches the PV,
and that the PV's `claimRef` was actually cleared (step 1).

### Step 3: wire the Deployment to the PVC
Edit `~/mariadb-deployment.yaml`, adding a `volumes:` section under
`spec.template.spec` referencing the PVC:

```yaml
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: mariadb
```

The full Pod spec block should now look like:

```yaml
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
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: mariadb
```

### Step 4: apply and verify
```bash
kubectl apply -f ~/mariadb-deployment.yaml
kubectl rollout status deploy/mariadb -n mariadb
kubectl get pods -n mariadb
```

Confirm the data really did survive:
```bash
kubectl exec -n mariadb deploy/mariadb -- cat /var/lib/mysql/RESTORE_MARKER
# restored-mariadb-data-<timestamp> — proves it's the SAME PV, not a fresh empty one
```

---

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash
NS=mariadb

phase=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$phase" == "Bound" ]] && echo "PASS: PVC mariadb is Bound" || echo "FAIL: PVC phase is '${phase:-missing}'"

vol=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.spec.volumeName}' 2>/dev/null)
[[ "$vol" == "mariadb-pv" ]] && echo "PASS: PVC is bound to the existing PV mariadb-pv" \
  || echo "FAIL: PVC bound to '${vol:-nothing}' instead of mariadb-pv"

am=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.spec.accessModes[0]}')
[[ "$am" == "ReadWriteOnce" ]] && echo "PASS: accessMode is ReadWriteOnce" || echo "FAIL: accessMode is '$am'"

sz=$(kubectl get pvc mariadb -n $NS -o jsonpath='{.spec.resources.requests.storage}')
[[ "$sz" == "250Mi" ]] && echo "PASS: storage request is 250Mi" || echo "FAIL: storage request is '$sz'"

claim=$(kubectl get deploy mariadb -n $NS -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null)
[[ "$claim" == "mariadb" ]] && echo "PASS: Deployment volume references PVC 'mariadb'" \
  || echo "FAIL: Deployment references claim '${claim:-none}'"

ready=$(kubectl get deploy mariadb -n $NS -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ "$ready" -ge 1 ]] 2>/dev/null && echo "PASS: mariadb Deployment has $ready ready replica(s)" \
  || echo "FAIL: mariadb Deployment not ready"

marker=$(kubectl exec -n $NS deploy/mariadb -- cat /var/lib/mysql/RESTORE_MARKER 2>/dev/null)
[[ "$marker" == restored-mariadb-data-* ]] && echo "PASS: original data is present ($marker)" \
  || echo "FAIL: RESTORE_MARKER missing — Deployment may be using a different/new volume"
```

Success criteria:

- PVC `mariadb` is `Bound` and `spec.volumeName` is `mariadb-pv` (the
  pre-existing PV, not a newly dynamically provisioned one).
- Access mode `ReadWriteOnce`, storage `250Mi`.
- `~/mariadb-deployment.yaml` (as applied) mounts that PVC.
- The Deployment is `Running`/ready, and `RESTORE_MARKER` inside the
  container proves the original data survived.

---

## 5. Cleanup
```bash
kubectl delete namespace mariadb
kubectl delete pv mariadb-pv
```

## 6. Optional extensions

- Instead of clearing `claimRef`, try setting `spec.volumeName: mariadb-pv`
  directly on the new PVC while the stale `claimRef` is still present, and
  observe that it still won't bind — the PV's claimRef takes priority, so
  clearing it really is required.
- Change `persistentVolumeReclaimPolicy` to `Delete` on a scratch PV and
  compare what happens to the underlying data when its PVC is deleted.
- Add a `StorageClass` with `volumeBindingMode: WaitForFirstConsumer` and
  discuss why that doesn't help here (this is static, pre-provisioned
  storage, not dynamic provisioning).
- Practice the same recovery with an `emptyDir`-backed StatefulSet using
  `volumeClaimTemplates` instead of a Deployment, and discuss why
  StatefulSets are usually the better fit for real databases.
