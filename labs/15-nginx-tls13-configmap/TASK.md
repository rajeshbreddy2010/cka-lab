# Lab: Restrict NGINX to TLSv1.3 Only (namespace `nginx-static`)

## Scenario
An NGINX Deployment named `nginx-static` is running in the `nginx-static`
namespace. It is configured using a ConfigMap named `nginx-config`.

## Task
Update the `nginx-config` ConfigMap to allow only **TLSv1.3** connections.

You may re-create, restart, or scale resources as necessary.

You can use the following command to test the changes:

```bash
curl --tls-max 1.2 https://web.k8s.local
```

(After the fix, this command should **fail** to connect — it's forcing
TLS 1.2, which should now be rejected.)

---

## 0. Prerequisites

This needs a resolvable hostname pointing at the node running the Pod, and
port 443 reachable from wherever you run `curl`. The setup below uses
`hostNetwork: true` pinned to one node, plus a hosts-file entry, to keep
this runnable on a small kind/minikube/kubeadm cluster without needing a
real Ingress controller or LoadBalancer.

---
