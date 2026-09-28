#!/usr/bin/env bash
kubectl delete gateway web-gateway --ignore-not-found
kubectl delete httproute web-route --ignore-not-found
kubectl delete ingress web --ignore-not-found
kubectl delete deploy web api --ignore-not-found
kubectl delete svc web-service api-service --ignore-not-found
kubectl delete secret web-tls --ignore-not-found
kubectl delete gatewayclass eg --ignore-not-found
echo "Envoy Gateway itself was left installed. To remove it too:"
echo "  kubectl delete -f https://github.com/envoyproxy/gateway/releases/download/v1.7.0/install.yaml"
