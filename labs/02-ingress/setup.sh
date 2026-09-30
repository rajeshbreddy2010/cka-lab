#!/usr/bin/env bash
# Builds the "starting state" the exam question assumes:
#   - ingress-nginx installed (IngressClass "nginx")
#   - namespace sound-repeater
#   - Deployment "echo" listening on 8080
# It does NOT create the Service or Ingress - that's your job.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-existing}"   # existing | kind
NS=sound-repeater

if [[ "$MODE" == "kind" ]]; then
  if ! kind get clusters 2>/dev/null | grep -q '^ingress-lab$'; then
    kind create cluster --name ingress-lab --config kind-cluster.yaml
  fi
  kubectl config use-context kind-ingress-lab
  kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
else
  # Existing kubeadm/k3s/minikube cluster. Install ingress-nginx yourself if missing:
  if ! kubectl get ingressclass nginx >/dev/null 2>&1; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml
  fi
fi

echo "Waiting for ingress controller..."
kubectl -n ingress-nginx wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s

kubectl apply -f deployment.yaml
kubectl -n "$NS" rollout status deploy/echo --timeout=120s

# example.org must resolve to your ingress entrypoint
if [[ "$MODE" == "kind" ]]; then
  if ! grep -q 'example.org' /etc/hosts; then
    echo "127.0.0.1 example.org" | sudo tee -a /etc/hosts
  fi
else
  echo
  echo "Existing cluster: add '<node-ip> example.org' to /etc/hosts."
  echo "Baremetal ingress-nginx listens on a NodePort, so test with:"
  echo "  kubectl -n ingress-nginx get svc ingress-nginx-controller"
  echo "  curl --resolve example.org:<http-nodeport>:<node-ip> http://example.org:<http-nodeport>/echo"
fi

echo
echo "Lab ready. Your task: create Service echoserver-service + Ingress echo in namespace $NS."
