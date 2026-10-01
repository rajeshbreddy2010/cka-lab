#!/usr/bin/env bash
kubectl delete ns sound-repeater --ignore-not-found
# Full teardown if you used kind:
#   kind delete cluster --name ingress-lab
#   sudo sed -i '/example.org/d' /etc/hosts
