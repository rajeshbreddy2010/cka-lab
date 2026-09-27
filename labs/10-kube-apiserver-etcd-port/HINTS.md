## Hints
1. If `kubectl` can't connect at all, the apiserver container itself is the
   problem — go straight to the node, not `kubectl`.
2. Static Pods for the control plane live at
   `/etc/kubernetes/manifests/*.yaml` and are managed directly by the
   kubelet, not by the scheduler — editing the file and saving it is enough
   to trigger a restart, no `kubectl apply` involved (and no apiserver
   needed to do it).
3. Since `kubectl` is down, use the container runtime CLI directly:
   `crictl ps -a`, `crictl logs <id>`, or `docker ps -a` / `docker logs
   <id>` depending on the runtime.
4. etcd exposes two different ports: **2379** for client requests (what
   apps/apiserver talk to) and **2380** for peer-to-peer Raft traffic
   between etcd members. Pointing `--etcd-servers` at 2380 means the
   apiserver is speaking the wrong protocol to the wrong listener entirely.
5. `grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml` shows
   exactly what the apiserver is currently configured to connect to.
6. After fixing the manifest, the kubelet detects the file change and
   restarts the static Pod automatically — you don't need to restart
   anything else yourself.

---
