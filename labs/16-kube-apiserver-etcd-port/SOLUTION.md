## Solution
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
