#!/usr/bin/env bash
# Creates a disposable kind cluster with NO CNI installed - the exam's starting state.
# Do NOT point this at your main cluster; it creates and uses its own kind cluster/context.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v kind >/dev/null 2>&1; then
  echo "ERROR: 'kind' is not installed. This lab needs its own disposable cluster." >&2
  echo "Install kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation" >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -q '^cni-lab$'; then
  kind create cluster --name cni-lab --config kind-cluster.yaml
fi
kubectl config use-context kind-cni-lab

echo
echo "Cluster ready with NO CNI installed. Nodes will show NotReady until you install one:"
kubectl get nodes
echo
echo "Your task: install Calico v3.28.2 (see TASK.md) using manifest files, not Helm."
