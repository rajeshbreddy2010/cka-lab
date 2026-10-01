# Lab: Streaming Sidecar for an Existing Deployment

## Task
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

## Why this is different from the bare-Pod version of this question
This is a **Deployment**, not a bare Pod. A Deployment's `spec.template` can
be freely changed — adding a container, adding a volume, anything — because
the Deployment controller handles it for you: it creates a new ReplicaSet
from the updated template and rolls the old Pods out as new ones come up.
A plain `kubectl apply -f deployment.yaml` with your changes is enough; you
never touch `kubectl delete`, and there's no dangerous immutable-field error
to work around.

(If you haven't already, it's worth comparing this to the bare-Pod version
of this same task — there, `spec.containers` and `spec.volumes` are
immutable on a running Pod, so the only way to add a sidecar is delete and
recreate. That contrast is the real lesson both labs are testing.)

## Approach
```bash
kubectl get deploy synergy-leverager -o yaml > deploy.yaml
```
Edit `deploy.yaml`:
1. Add a Volume (e.g. `emptyDir`) under `spec.template.spec.volumes`.
2. Add a `volumeMounts` entry for that volume, `mountPath: /var/log`, to the
   **existing** container — this is the "adding the required volume mount"
   the task allows. Don't touch its `command`, `image`, or anything else.
3. Add the new `sidecar` container: image `busybox:stable`, the `tail`
   command above, and the same volume mounted at `/var/log`.
4. `kubectl apply -f deploy.yaml`

Or skip straight to editing live:
```bash
kubectl edit deploy synergy-leverager
```
Either works, since `apply`/`edit` on a Deployment template is always allowed.

## Gotchas
- `command` as a single shell string becomes a 3-item YAML list:
  `["/bin/sh", "-c", "tail -n+1 -f /var/log/synergy-leverager.log"]`.
- Both containers must mount the **same** volume at the **same path**
  (`/var/log`) — a sidecar with its own separate `emptyDir` would never see
  the file the main container writes.
- "Do not modify the specification of the existing container other than
  adding the required volume mount" means exactly that: don't reformat its
  `command`, don't add `resources`, don't rename it. Add only the
  `volumeMounts` entry.
- Applying the change triggers a rollout: the old Pod terminates and a new
  one (with both containers) starts. A few seconds of unavailability is
  expected and fine here (`replicas: 1`).
- Verify with `kubectl logs deploy/synergy-leverager -c sidecar --tail=5 -f`
  — you should see new lines every ~5 seconds.

## Check / reset
```bash
chmod +x *.sh
./check.sh
./cleanup.sh
```
