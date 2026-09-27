## Solution
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
