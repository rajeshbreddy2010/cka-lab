# Lab: Streaming Sidecar Containers for Logging

Two related tasks: adding a log-streaming sidecar to a **Deployment** and to a
bare **Pod**. Both use the same pattern — a shared `emptyDir` Volume mounted
at `/var/log`, with a `busybox` sidecar tailing the log file so
`kubectl logs <pod> -c sidecar` exposes it through the normal logging
pipeline.

---

## Task A — Deployment `synergy-leverager` (namespace `default`, or as set up)

Update the existing Deployment `synergy-leverager`, adding a co-located
container named `sidecar` using the `busybox:stable` image to the existing
Pod. The new co-located container has to run the following command:

```
/bin/sh -c "tail -n+1 -f /var/log/synergy-leverager.log"
```

Use a Volume mounted at `/var/log` to make the log file
`synergy-leverager.log` available to the co-located container.

**Do not modify the specification of the existing container other than
adding the required volume mount.**

## Task B — bare Pod `big-corp-app`

An existing Pod needs to be integrated into the Kubernetes built-in logging
architecture (e.g. `kubectl logs`). Adding a streaming sidecar container is a
good and common way to accomplish this requirement.

Add a sidecar container named `sidecar`, using the `busybox` image, to the
existing Pod `big-corp-app`. The new sidecar container has to run the
following command:

```
/bin/sh -c tail -n+1 -f /var/log/big-corp-app.log
```

Use a Volume, mounted at `/var/log`, to make the log file
`big-corp-app.log` available to the sidecar container.

---

## 1. Setup (run as instructor / before the exercise)

Both workloads write logs to a file inside their own container filesystem —
`/var/log` is **not yet shared** with anything, so `kubectl logs` only shows
nothing useful and there's no way to see the log stream through the normal
logging path. That's the gap the exercise closes.

```bash
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
```

---

## 2. Hints (reveal one at a time)

1. `kubectl logs <pod>` only shows a container's **stdout/stderr**, not
   arbitrary files. A sidecar that `tail -f`s the file and prints to its own
   stdout makes that file visible via `kubectl logs <pod> -c sidecar`.
2. For the file to exist in the sidecar's filesystem at all, the sidecar and
   the app container must share a **Volume** — an `emptyDir` mounted at
   `/var/log` in both containers is enough (they don't need persistence
   beyond the Pod's lifetime).
3. A running Deployment's Pod template can't be edited in place with
   `kubectl exec`; edit the Deployment (`kubectl edit deploy ...` or a
   patch) and let it roll a new Pod.
4. A bare Pod's spec (other than a few fields) is immutable — you can't
   `kubectl edit` most of it. You need to delete and recreate the Pod (or
   `kubectl replace --force -f`) with the sidecar and Volume added.
5. `kubectl get deploy synergy-leverager -o yaml` / `kubectl get pod
   big-corp-app -o yaml` gives you a starting point to copy and edit.
6. The task says not to change anything about the existing container besides
   the volume mount — keep its `command`/`args`/`image` untouched.

---

## 3. Solution

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

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash

echo "--- Task A: synergy-leverager ---"
c=$(kubectl get deploy synergy-leverager -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].image}')
[[ "$c" == "busybox:stable" ]] && echo "PASS: sidecar image is busybox:stable" || echo "FAIL: sidecar image is '${c:-missing}'"

cmd=$(kubectl get deploy synergy-leverager -o jsonpath='{.spec.template.spec.containers[?(@.name=="sidecar")].command}')
echo "$cmd" | grep -q "tail -n+1 -f /var/log/synergy-leverager.log" \
  && echo "PASS: sidecar command matches" || echo "FAIL: sidecar command is '$cmd'"

mnt=$(kubectl get deploy synergy-leverager -o jsonpath='{.spec.template.spec.containers[?(@.name=="synergy-leverager")].volumeMounts[?(@.mountPath=="/var/log")].name}')
[[ -n "$mnt" ]] && echo "PASS: original container has /var/log mounted" || echo "FAIL: original container missing /var/log mount"

ready=$(kubectl get deploy synergy-leverager -o jsonpath='{.status.readyReplicas}')
[[ "$ready" -ge 1 ]] 2>/dev/null && echo "PASS: Deployment has $ready ready replica(s)" || echo "FAIL: no ready replicas"

out=$(kubectl logs deploy/synergy-leverager -c sidecar --tail=3 2>/dev/null)
[[ -n "$out" ]] && echo "PASS: sidecar is streaming log lines" || echo "FAIL: no output from sidecar logs"

echo
echo "--- Task B: big-corp-app ---"
c=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="sidecar")].image}')
[[ "$c" == busybox* ]] && echo "PASS: sidecar image is $c" || echo "FAIL: sidecar image is '${c:-missing}'"

cmd=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="sidecar")].command}')
echo "$cmd" | grep -q "tail -n+1 -f /var/log/big-corp-app.log" \
  && echo "PASS: sidecar command matches" || echo "FAIL: sidecar command is '$cmd'"

mnt=$(kubectl get pod big-corp-app -o jsonpath='{.spec.containers[?(@.name=="big-corp-app")].volumeMounts[?(@.mountPath=="/var/log")].name}')
[[ -n "$mnt" ]] && echo "PASS: original container has /var/log mounted" || echo "FAIL: original container missing /var/log mount"

phase=$(kubectl get pod big-corp-app -o jsonpath='{.status.phase}')
[[ "$phase" == "Running" ]] && echo "PASS: Pod is Running" || echo "FAIL: Pod phase is $phase"

out=$(kubectl logs big-corp-app -c sidecar --tail=3 2>/dev/null)
[[ -n "$out" ]] && echo "PASS: sidecar is streaming log lines" || echo "FAIL: no output from sidecar logs"
```

Success criteria (both tasks):

- Sidecar container named `sidecar`, correct image, correct `tail` command.
- A Volume mounted at `/var/log` in **both** the sidecar and the original
  container.
- The original container's image/command/args are unchanged.
- `kubectl logs <workload> -c sidecar` streams the log file's contents.

---

## 5. Cleanup

```bash
kubectl delete deployment synergy-leverager --ignore-not-found
kubectl delete pod big-corp-app --ignore-not-found
```

## 7. Common mistakes (from real attempts)

These come up often enough with hand-edited YAML that they're worth calling
out before you start:

- **Sidecar indented one level too deep or too shallow.** Every item in the
  `containers:` list must start with `-` at the **same column**. If
  `- name: sidecar` doesn't line up exactly under `- name: <original>` (or
  `- args:`), YAML will read it as a field of the previous container instead
  of a second container — this can pass YAML parsing but fail the API
  schema, or worse, silently produce the wrong object.
- **Two `volumes:` keys in the same mapping.** If you paste content twice
  while editing, you can end up with `volumes:` appearing twice under
  `spec:`. YAML keeps only the **last** one, so the first list (often the
  one with your `logs` volume) is silently discarded — you'll then get
  `volumeMounts[...].name: Not found: "logs"` when you apply.
- **Reusing the wrong task's values.** If you're doing both the Deployment
  and the Pod version back to back, it's easy to paste the wrong log
  filename (`synergy-leverager.log` vs `big-corp-app.log`) into the sidecar
  command.
- **Volume mount path typo on the *original* container.** The sidecar can be
  perfectly correct, but if the original container's `volumeMounts` still
  points somewhere other than `/var/log` (e.g. `/opt`), the log file is
  never actually shared and the sidecar has nothing to tail.
- **Editing a live Pod's `-o yaml` dump directly.** It still contains
  `status:`, `resourceVersion`, `uid`, `nodeName`, and an auto-injected
  `kube-api-access-...` volume/mount. These aren't wrong to leave in, but
  they add noise and risk of a misplaced list item; it's simpler to write a
  minimal spec from scratch with just what the task asks for.

**Before running the real command, always dry-run it:**

```bash
kubectl apply --dry-run=client -f synergy-leverager.yaml -o yaml | less
kubectl replace --dry-run=client --force -f big-corp.yaml -o yaml | less
```

If the dry-run output doesn't show `sidecar` as a clean sibling of the
original container under `containers:`, and exactly one `volumes:` entry
named `logs`, fix the file before touching the cluster.

## 8. Optional extensions

- Switch `emptyDir` for `emptyDir: {sizeLimit: 100Mi}` and discuss what
  happens if the log file grows past that.
- Add a second sidecar that also tails the file but filters for a keyword
  (e.g. `grep ERROR`), to show multiple containers reading the same Volume.
- Try mounting the Volume read-only (`readOnly: true`) in the sidecar only,
  since it never needs to write to `/var/log`.
- Compare this pattern to a **logging agent sidecar** that ships the file to
  an external system instead of just re-exposing it via stdout.

