# Lab: Broken kube-apiserver After an etcd Migration (wrong etcd port)

## Scenario
After a cluster migration, the control plane's `kube-apiserver` is not
coming up. Before the migration, etcd was **external** and running in HA.
After the migration, the kube-apiserver's manifest was left pointing at
etcd's **peer port (2380)** instead of its **client port (2379)**.

## Task
Fix it. `kube-apiserver` must come back up and the cluster must become
healthy again.

---

## 0. Prerequisites

This is a **kubeadm-style static-Pod** scenario — it requires root/SSH
access to the control plane node's filesystem (`/etc/kubernetes/manifests`),
not just a `kubectl` connection (which won't work anyway once the apiserver
is down). It also assumes an **external** etcd cluster already configured
in `kube-apiserver`'s manifest (`--etcd-servers=https://<ip>:2379,...`), as
described in the scenario. If your practice cluster uses kubeadm's default
**stacked** (local) etcd instead, adapt the setup script's `sed` target to
match your actual `--etcd-servers` value first.

---

## 1. Setup (run as instructor / before the exercise, ON the control plane node)

```bash
#!/usr/bin/env bash
set -euo pipefail

MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
BACKUP=/root/kube-apiserver.yaml.good

[[ -f "$MANIFEST" ]] || { echo "kube-apiserver.yaml not found at $MANIFEST"; exit 1; }

cp "$MANIFEST" "$BACKUP"
echo "Backed up working manifest to $BACKUP"

grep -o -- '--etcd-servers=[^ "]*' "$MANIFEST" || {
  echo "No --etcd-servers flag found -- is this a stacked-etcd cluster? Adjust manually."
  exit 1
}

# Break it: swap every etcd client port 2379 for the peer port 2380
sed -i 's/:2379/:2380/g' "$MANIFEST"

echo
echo "Manifest broken. kubelet will notice the change and restart kube-apiserver"
echo "within ~20-60s (static Pods are re-read from disk automatically)."
echo
echo "New --etcd-servers value:"
grep -o -- '--etcd-servers=[^ "]*' "$MANIFEST"
echo
echo "Watch it fail with:"
echo "  crictl ps -a | grep kube-apiserver"
echo "  crictl logs \$(crictl ps -a --name kube-apiserver -q | head -1)"
```

**Expected broken state**

```bash
kubectl get nodes
# The connection to the server <ip>:6443 was refused

crictl ps -a | grep kube-apiserver
# STATE = Exited, repeatedly restarting

crictl logs <kube-apiserver-container-id>
# something like:
# "rpc error: code = Unknown desc = malformed header: missing HTTP content-type"
# or context deadline exceeded / connection errors talking to etcd,
# because 2380 speaks the etcd peer (Raft) protocol, not the client gRPC/HTTP API.
```

---

## 2. Hints (reveal one at a time)

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

## 3. Solution

### Step 1: confirm the apiserver is actually down, and why
```bash
kubectl get nodes
# refused / timeout

crictl ps -a | grep kube-apiserver
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1)
```

### Step 2: inspect the manifest
```bash
grep -o -- '--etcd-servers=[^ "]*' /etc/kubernetes/manifests/kube-apiserver.yaml
# --etcd-servers=https://10.0.0.11:2380,https://10.0.0.12:2380,https://10.0.0.13:2380
```
2380 is the giveaway — that's etcd's peer port, not its client port.

### Step 3: fix it
```bash
sudo sed -i 's/:2380/:2379/g' /etc/kubernetes/manifests/kube-apiserver.yaml
grep -o -- '--etcd-servers=[^ "]*' /etc/kubernetes/manifests/kube-apiserver.yaml
# --etcd-servers=https://10.0.0.11:2379,https://10.0.0.12:2379,https://10.0.0.13:2379
```

> Be careful with a blind `:2380` → `:2379` replace if the manifest has
> other unrelated `:2380` references (it normally won't for
> `kube-apiserver.yaml`, but always `grep` first and confirm you're only
> touching `--etcd-servers`).

If you'd rather restore from a known-good backup instead of editing in
place:
```bash
sudo cp /root/kube-apiserver.yaml.good /etc/kubernetes/manifests/kube-apiserver.yaml
```

### Step 4: wait for the kubelet to pick it up and verify
```bash
watch crictl ps -a | grep kube-apiserver
# wait for a fresh container with STATE = Running and rising uptime

kubectl get nodes
kubectl get componentstatuses 2>/dev/null || kubectl get --raw='/readyz?verbose'
kubectl get pods -n kube-system
```

All control plane static Pods (`kube-apiserver`, `kube-controller-manager`,
`kube-scheduler`) and etcd (if co-located) should show `Running`, and
`kubectl get nodes` should respond normally again.

---

## 4. Verification / checker

Save as `check.sh` (run on the control plane node):

```bash
#!/usr/bin/env bash

port_check=$(grep -o -- '--etcd-servers=[^ "]*' /etc/kubernetes/manifests/kube-apiserver.yaml)
echo "$port_check" | grep -q ':2380' \
  && echo "FAIL: manifest still references etcd peer port 2380: $port_check" \
  || echo "PASS: manifest no longer points at port 2380"
echo "$port_check" | grep -q ':2379' \
  && echo "PASS: manifest points at etcd client port 2379" \
  || echo "FAIL: manifest doesn't reference port 2379 at all -- check --etcd-servers"

if kubectl get nodes >/dev/null 2>&1; then
  echo "PASS: kubectl can reach the apiserver"
else
  echo "FAIL: kubectl still cannot reach the apiserver"
fi

state=$(crictl ps --name kube-apiserver -o json 2>/dev/null | grep -o '"state": *"[A-Z_]*"' | head -1)
echo "$state" | grep -q RUNNING \
  && echo "PASS: kube-apiserver container is Running" \
  || echo "FAIL: kube-apiserver container state: ${state:-not found}"

ready=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
echo "$ready" | grep -q False \
  && echo "FAIL: at least one node is NotReady" \
  || echo "PASS: all visible nodes report Ready"
```

Success criteria:

- `kube-apiserver.yaml`'s `--etcd-servers` flag uses port `2379` on every
  member, not `2380`.
- `kube-apiserver`'s static Pod container is `Running` and stable (not
  restarting).
- `kubectl get nodes` succeeds and reports nodes as `Ready`.
- Other control plane components in `kube-system` are healthy.

---

## 5. Cleanup
```bash
sudo cp /root/kube-apiserver.yaml.good /etc/kubernetes/manifests/kube-apiserver.yaml
rm -f /root/kube-apiserver.yaml.good
```

## 6. Optional extensions

- Break a different flag instead (`--etcd-cafile`, `--etcd-certfile`
  pointing at the wrong path) and practice diagnosing TLS-handshake style
  failures versus wrong-port failures — the `crictl logs` output differs
  noticeably between the two.
- Simulate the same class of mistake on `kube-controller-manager` or
  `kube-scheduler`'s manifest (e.g. a bad `--kubeconfig` path) instead of
  `kube-apiserver`, to compare how "less critical" static Pods fail more
  quietly (cluster still partly usable) versus apiserver failing (cluster
  fully unreachable).
- Test recovery when there's **no backup file at all** — walk through
  finding the right etcd port from `etcdctl member list` (run directly
  against etcd) instead of trusting a saved copy.
- Explore `journalctl -u kubelet -f` alongside `crictl logs` to see the
  kubelet's own view of a static Pod repeatedly failing its restart
  backoff.
