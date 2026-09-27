## Hints
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
