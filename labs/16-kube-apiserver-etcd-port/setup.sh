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
