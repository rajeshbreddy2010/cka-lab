# Lab: Streaming Sidecar for an Existing Pod

An existing Pod needs to be integrated into the Kubernetes built-in logging
architecture (e.g. `kubectl logs`). Adding a streaming sidecar container is a
good and common way to accomplish this.

## Task
Add a sidecar container named `sidecar`, using the `busybox` image, to the
existing Pod `big-corp-app`. The new sidecar container has to run the
following command:
```
/bin/sh -c "tail -n+1 -f /var/log/big-corp-app.log"
```
Use a Volume, mounted at `/var/log`, to make the log file
`big-corp-app.log` available to the sidecar container.

## Why `kubectl edit` won't work
`big-corp-app` is a **bare Pod**, not a Deployment. A Pod's `spec.containers`
and `spec.volumes` are **immutable** once it's created — the API server
rejects any attempt to add, remove, or change them on a running Pod:
```
The Pod "big-corp-app" is invalid: spec: Forbidden: pod updates may not
add or remove containers
```
`kubectl edit pod big-corp-app` will let you open the editor, but saving the
change fails with exactly that error. There is no Deployment/ReplicaSet
here to do a rolling update for you — you have to replace the Pod yourself.

## Approach
```bash
# 1. Export the current Pod definition
kubectl get pod big-corp-app -o yaml > pod-fixed.yaml

# 2. Edit pod-fixed.yaml:
#    - add a Volume (e.g. emptyDir) to spec.volumes
#    - add that volume's volumeMount at /var/log to the EXISTING container
#      (it already writes to /var/log/big-corp-app.log; mounting a volume
#      there doesn't change that path, just backs it with shared storage)
#    - add the new "sidecar" container (busybox image, the tail command, same
#      volumeMount at /var/log)
#    - strip the server-managed fields so it can be re-created cleanly:
#      metadata.resourceVersion, metadata.uid, metadata.creationTimestamp,
#      metadata.annotations (kubectl.kubernetes.io/last-applied-configuration),
#      spec.nodeName, the whole status: block

# 3. Replace the Pod
kubectl delete pod big-corp-app
kubectl apply -f pod-fixed.yaml
```

## Gotchas
- Deleting the old Pod means a short gap with no `big-corp-app` running —
  that's expected and unavoidable for a bare Pod. (This is exactly why
  real workloads use a Deployment instead of a bare Pod — so ask yourself
  why that distinction matters next time you design one.)
- `emptyDir` storage does not survive the Pod being deleted. The log
  history up to that point is lost either way (the old container's
  filesystem is gone too) — only new lines written after recreation will
  show up in the sidecar's tail. That's fine; the task is about wiring,
  not about preserving history.
- Don't forget to mount the volume on the **existing** container too, not
  just the new one — both the writer and the reader (`tail -f`) need to
  see the same file, which means the same shared volume mounted at the
  same path in both containers.
- `command` in the task (`/bin/sh -c "tail -n+1 -f ..."`) is one string,
  so as a YAML list it's three list items: `["/bin/sh", "-c", "tail -n+1 -f /var/log/big-corp-app.log"]`.
- Verify before celebrating:
  `kubectl logs big-corp-app -c sidecar --tail=5 -f` — you should see new
  lines appear every few seconds.

## Check / reset
```bash
chmod +x *.sh
./check.sh
./cleanup.sh
```
