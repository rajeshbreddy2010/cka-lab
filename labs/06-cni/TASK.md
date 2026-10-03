# Lab: Install a CNI (CKA Question 6)

## Task
Install and set up a Container Network Interface (CNI) that meets these requirements:

Pick and install **one** of these CNI options:

- **Flannel v0.26.1**
  Manifest: https://github.com/flannel-io/flannel/releases/download/v0.26.1/kube-flannel.yml
- **Calico v3.28.2**
  Manifest: https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml

The CNI you choose must:
- Let Pods communicate with each other
- Support NetworkPolicy enforcement

Install from manifest files (do not use Helm).

## The catch
Read the requirements carefully. **Flannel does not implement NetworkPolicy —
it only provides pod-to-pod networking.** A cluster running only Flannel
will let Pods communicate, but any `NetworkPolicy` object you create will be
silently ignored: nothing actually blocks the traffic it describes.

Since the task requires **both** "Pods communicate" **and** "NetworkPolicy
enforcement," Flannel fails the second requirement no matter how correctly
you install it. **Calico is the only option of the two that satisfies both
requirements.** This is a common CKA trap — don't pick the CNI you know best,
pick the one the requirements actually allow.

(If you only needed pod-to-pod connectivity with no NetworkPolicy requirement,
Flannel would be a perfectly valid, simpler choice — that's why it's worth
knowing both installs.)

## Why this needs its own cluster
This task assumes a cluster with **no CNI installed yet** — that's the normal
starting state in the real exam. Installing a second CNI on top of one
that's already running (e.g. your existing Cilium cluster) does not work:
the two CNIs conflict over pod IP allocation and iptables/eBPF rules, and can
break pod networking on your whole cluster, taking every other lab down
with it.

**Do not run this lab's `setup.sh` against your main controlplane cluster.**
Use a disposable `kind` cluster instead — `setup.sh` creates one for you
with `disableDefaultCNI: true`, so it starts with zero networking, matching
the exam's starting state.

## Run
```bash
chmod +x *.sh
./setup.sh      # creates a fresh, CNI-less kind cluster named "cni-lab"
```
Then install Calico yourself using the two manifests below, before peeking
at `solution.sh`.

## Calico install (2 steps: operator, then the actual install)
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml
```
The first manifest installs the Tigera operator (a controller) and its CRDs.
The second is a `default` `Installation` custom resource that tells the
operator to actually deploy Calico using those CRDs. Both are manifest
files — no Helm involved, satisfying that requirement.

## Check / reset
```bash
./check.sh
./cleanup.sh    # deletes the whole kind cluster
```

## Verify manually
```bash
kubectl get pods -n calico-system              # calico-node, calico-kube-controllers, etc. all Running
kubectl get nodes                               # should go Ready once Calico is up
kubectl get tigerastatus                        # all components "Available: True"
```
Then prove NetworkPolicy actually works — create two Pods, apply a
default-deny NetworkPolicy, and confirm traffic is blocked (see
`solution.sh` for a ready-made test).

## Gotchas
- Calico's node status can take 1-3 minutes to go Ready after the manifests
  are applied — the operator has to pull images and reconcile.
- `kubectl create` (not `apply`) is Calico's documented method here, since
  the CRDs are large and `apply` can hit the annotation-size limit on some of
  them. `create` avoids that entirely for a first install.
- If pods stay `Pending`/`ContainerCreating` after both manifests are
  applied, check `kubectl get tigerastatus` — usually one component is still
  reconciling, not actually broken.
- Don't confuse "CNI installed" with "CNI enforcing policy" — a plain
  `kubectl get pods -n calico-system` all-Running is necessary but not
  sufficient proof; the NetworkPolicy test in `solution.sh` is what actually
  proves the second requirement.
