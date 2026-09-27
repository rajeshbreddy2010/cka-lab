## Solution
### Task A: synergy-leverager (Deployment)

```bash
kubectl get deploy synergy-leverager -o yaml > synergy-leverager.yaml
```

Edit `synergy-leverager.yaml`'s Pod template to add the Volume, the existing
container's mount, and the sidecar:

```yaml
spec:
  template:
    spec:
      volumes:
      - name: logs
        emptyDir: {}
      containers:
      - name: synergy-leverager
        # image/command/args unchanged
        volumeMounts:
        - name: logs
          mountPath: /var/log
      - name: sidecar
        image: busybox:stable
        command: ["/bin/sh", "-c", "tail -n+1 -f /var/log/synergy-leverager.log"]
        volumeMounts:
        - name: logs
          mountPath: /var/log
```

Apply it:

```bash
kubectl apply -f synergy-leverager.yaml
kubectl rollout status deploy/synergy-leverager
```

Or patch it directly without a manual file edit:

```bash
kubectl patch deploy synergy-leverager --type=strategic -p '
{
  "spec": {
    "template": {
      "spec": {
        "volumes": [{"name": "logs", "emptyDir": {}}],
        "containers": [
          {"name": "synergy-leverager", "volumeMounts": [{"name": "logs", "mountPath": "/var/log"}]},
          {"name": "sidecar", "image": "busybox:stable",
           "command": ["/bin/sh", "-c", "tail -n+1 -f /var/log/synergy-leverager.log"],
           "volumeMounts": [{"name": "logs", "mountPath": "/var/log"}]}
        ]
      }
    }
  }
}'
```

> Strategic merge patch merges containers by name, so `synergy-leverager`
> keeps its original `image`/`command`/`args` — you're only adding the
> `volumeMounts` field to it, matching "don't modify the existing container
> other than the volume mount."

Verify:

```bash
kubectl logs deploy/synergy-leverager -c sidecar --tail=5
```

### Task B: big-corp-app (bare Pod)

Bare Pods are mostly immutable, so export, edit, delete, recreate:

```bash
kubectl get pod big-corp-app -o yaml > big-corp-app.yaml
```

Trim the `status:` block and metadata noise (`resourceVersion`, `uid`,
`creationTimestamp`, `nodeName`, etc. — `kubectl replace --force` will
regenerate these), then add the Volume, mount, and sidecar the same way:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: big-corp-app
  labels:
    app: big-corp-app
spec:
  volumes:
  - name: logs
    emptyDir: {}
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
    volumeMounts:
    - name: logs
      mountPath: /var/log
  - name: sidecar
    image: busybox
    command: ["/bin/sh", "-c", "tail -n+1 -f /var/log/big-corp-app.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log
```

Replace the Pod:

```bash
kubectl replace --force -f big-corp-app.yaml
kubectl wait --for=condition=Ready pod/big-corp-app --timeout=60s
kubectl logs big-corp-app -c sidecar --tail=5
```

> `kubectl replace --force` deletes and recreates the object, which is fine
> here since the task is about the Pod's final spec, not about avoiding
> downtime.

---
