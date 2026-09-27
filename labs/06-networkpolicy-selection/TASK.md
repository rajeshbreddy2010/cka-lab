# Lab: Choose and Apply the Right NetworkPolicy (`frontend` / `backend`)

## Scenario
A `frontend` Deployment (namespace `frontend`) needs to reach a `backend`
Deployment (namespace `backend`). Several candidate NetworkPolicy YAML files
already exist on disk in `~/netpol`, written by a previous engineer. Some are
wrong, and one is dangerously permissive. Only one is correct.

## Task
Review and apply the appropriate NetworkPolicy from the provided YAML
samples. Ensure the chosen NetworkPolicy is **not overly permissive**, but
allows communication between the `frontend` and `backend` Deployments,
running in the `frontend` and `backend` namespaces respectively.

1. First, analyze the `frontend` and `backend` Deployments to determine the
   specific requirements for the NetworkPolicy that needs to be applied.
2. Next, examine the NetworkPolicy YAML samples in `~/netpol`.
3. **Do not delete or modify the provided samples. Only apply one of them.**
   Failure to comply may result in a reduced score.
4. Finally, apply the NetworkPolicy that enables communication between the
   `frontend` and `backend` Deployments, without being overly permissive.

---

## 0. Prerequisite: a CNI that enforces NetworkPolicy

`NetworkPolicy` objects are inert unless the cluster's CNI plugin enforces
them. Plain `kindnet` (kind's default) and plain `flannel` do **not**
enforce policies — everything will still be reachable no matter what you
apply, which makes the exercise unverifiable. Use a CNI that does, e.g.
Calico:

```bash
# kind cluster created with networking disabled, then Calico installed
kind create cluster --config kind-no-cni.yaml   # disableDefaultCNI: true
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```

Most managed exam environments already have this configured. If you're
building this at home and traffic is never blocked no matter what you
apply, check your CNI first before assuming your policy is wrong.

---
