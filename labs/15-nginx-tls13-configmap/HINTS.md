## Hints
1. `kubectl get cm nginx-config -n nginx-static -o yaml` shows the current
   `ssl_protocols` line inside the embedded `nginx.conf`.
2. Only remove `TLSv1.2` from `ssl_protocols` — don't touch the certificate
   or key lines, or the server won't start at all.
3. Editing a ConfigMap does **not** automatically make a running container
   re-read it. Kubernetes eventually syncs the mounted file on the node
   (after some delay, via kubelet's periodic sync), but nginx itself won't
   reload its config just because the file on disk changed — you still need
   to reload/restart the nginx process, most simply by restarting the Pod.
4. `kubectl rollout restart deployment nginx-static -n nginx-static` is the
   cleanest way to force new Pods (and thus a fresh nginx process) after
   editing the ConfigMap.
5. Since the Pod uses `hostNetwork: true` and is pinned to one node,
   restarting the Deployment doesn't move it elsewhere — the same node/IP
   still serves `web.k8s.local` after the restart.
6. If `curl` hangs or resets instead of giving a clean TLS error, that's
   still a pass — it means the handshake was rejected, which is the point.

---
