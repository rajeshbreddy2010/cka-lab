# Lab: Migrate Ingress to Gateway API

## Task
1. Create a **Gateway** named `web-gateway` with hostname `gateway.web.k8s.local`
   that keeps the existing **TLS and listener configuration** of the Ingress `web`.
2. Create an **HTTPRoute** named `web-route` with hostname `gateway.web.k8s.local`
   that keeps the existing **routing rules** of the Ingress `web`.
3. Test: `curl https://gateway.web.k8s.local`
4. Finally, **delete** the existing Ingress `web`.

## Run
```bash
chmod +x *.sh
./setup.sh      # installs Envoy Gateway + GatewayClass "eg", creates Ingress "web", backends, TLS Secret
```
Everything lives in the `default` namespace. Do the task yourself, then `./check.sh`.
`solution.yaml` has the answer.

## How to approach it
```bash
kubectl get ingress web -o yaml        # read: TLS secret, host, paths, backends
kubectl get gatewayclass               # you need this name for gatewayClassName
```
Translate field by field:

| Ingress | Gateway API |
|---|---|
| `spec.tls[].secretName` | Gateway `listeners[].tls.certificateRefs[].name` |
| `tls.hosts` / rule `host` | listener `hostname` and HTTPRoute `hostnames` |
| (implicit 443 HTTPS) | listener `protocol: HTTPS`, `port: 443`, `tls.mode: Terminate` |
| `paths[].path` + `pathType: Prefix` | HTTPRoute `matches[].path` type `PathPrefix` |
| `backend.service.name/port` | HTTPRoute `backendRefs[].name/port` |
| `ingressClassName` | Gateway `gatewayClassName` |

Docs (allowed in the exam): kubernetes.io -> "Migrating from Ingress" / gateway-api.sigs.k8s.io.
Handy: `kubectl explain gateway.spec.listeners.tls`.

## Testing on a bare-metal cluster
There is no cloud LoadBalancer, so the Gateway has no external IP. Reach the Envoy
proxy through its NodePort instead (`check.sh` does exactly this):
```bash
SVC=$(kubectl -n envoy-gateway-system get svc \
  -l gateway.envoyproxy.io/owning-gateway-name=web-gateway -o jsonpath='{.items[0].metadata.name}')
PORT=$(kubectl -n envoy-gateway-system get svc $SVC -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -k --resolve gateway.web.k8s.local:$PORT:$NODE_IP https://gateway.web.k8s.local:$PORT/
```
`-k` is needed because the cert is self-signed. In the real exam the environment
usually makes plain `curl https://gateway.web.k8s.local` work.

## Gotchas
- The Ingress `web` is not actually served here (no ingress controller is installed);
  the exercise is translating it. Don't worry that it never worked.
- The Gateway must reference the **same Secret** (`web-tls`), in the same namespace.
  A Secret in another namespace needs a ReferenceGrant.
- HTTPRoute needs `parentRefs` pointing at the Gateway, or it attaches to nothing.
- Check status, it tells you what is wrong:
  `kubectl describe gateway web-gateway` and `kubectl describe httproute web-route`
  (look at `Accepted` and `ResolvedRefs`).
- Delete the Ingress **last**, after the curl works.
- The Gateway's `Programmed` condition may stay False on bare metal because no external
  address is assigned; `Accepted: True` plus a working NodePort curl is what matters here.
