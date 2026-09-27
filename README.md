# Kubernetes Practice Labs

A set of self-contained, scenario-based Kubernetes labs (CKA/CKS/CKAD-style).
Each lab lives in its own folder under `labs/` with a task, hints, a full
solution, a setup script that breaks/builds the scenario, and a checker
script that verifies you solved it correctly.

## Requirements

- A disposable Kubernetes cluster you have `kubectl`/root access to (kind,
  minikube, k3d, kubeadm, etc.). **Do not run these against anything you
  care about** — several labs intentionally break things.
- `kubectl` configured against that cluster.
- Some labs have extra prerequisites (a CNI that enforces NetworkPolicy,
  `metrics-server`, `openssl`, root/SSH access to a control-plane node).
  Each lab's `README.md` calls these out under "Prerequisites"/"Setup".
- Bash, and normally root or sudo on at least one node for the couple of
  labs that touch node-level files.

## Usage

```bash
git clone <your-repo-url>
cd k8s-practice-labs
./run.sh            # lists all labs
./run.sh 01         # shows lab 01's task and offers to run its setup.sh
```

Or work a lab manually without the helper script:

```bash
cd labs/01-wordpress-resource-requests
cat TASK.md          # read the task
bash setup.sh         # break/build the scenario
# ... do the exercise using kubectl ...
bash check.sh         # verify your work
cat SOLUTION.md       # peek if you're stuck
bash cleanup.sh        # tear it down when you're done
```

Each lab is independent — they use their own namespaces, so you can do them
in any order, though a few (marked below) share cluster-level resources
(PriorityClasses, node labels, static Pod manifests) and are best run one at
a time on a scratch cluster.

## Labs

| # | Folder | Topic | Notes |
|---|---|---|---|
| 01 | `01-wordpress-resource-requests` | Pod resource requests, scheduling | Pins Pods to one node via a node label |
| 02 | `02-priorityclass-preemption` | PriorityClass, preemption | Pins to one node; creates cluster-scoped PriorityClasses |
| 03 | `03-logging-sidecar` | Sidecar containers, shared volumes | Two sub-tasks: a Deployment and a bare Pod |
| 04 | `04-frontend-nodeport-service` | Services, NodePort, containerPort | |
| 05 | `05-mariadb-pv-restore` | PV/PVC binding, `claimRef`, static provisioning | Uses `hostPath`; pins to one node |
| 06 | `06-networkpolicy-selection` | NetworkPolicy | **Requires a CNI that enforces NetworkPolicy** (see lab README) |
| 07 | `07-hpa-apache-server` | HorizontalPodAutoscaler | **Requires `metrics-server`** (installed by the lab's prerequisites step) |
| 08 | `08-cert-manager-verify-crds` | CRDs, `kubectl explain`, verifying an app | Installs cert-manager |
| 09 | `09-nginx-tls13-configmap` | ConfigMaps, TLS, config reload semantics | Uses `hostNetwork`; needs `openssl` and a `/etc/hosts` entry |
| 10 | `10-kube-apiserver-etcd-port` | Static Pods, control-plane troubleshooting | **Node-level only, no `kubectl`.** Requires root/SSH on a kubeadm control-plane node. Breaks the real apiserver — use a fully disposable cluster. |

## Folder layout

```
labs/<NN-name>/
  README.md    full write-up (scenario, task, prerequisites, setup, hints, solution, checker, cleanup, extensions)
  TASK.md      just the task text, for when you don't want spoilers nearby
  HINTS.md     progressive hints
  SOLUTION.md  full worked solution
  setup.sh     instructor/setup script -- builds or breaks the scenario
  check.sh     verifies your solution
  cleanup.sh   tears the lab down
```

## Safety notes

- Several labs (`01`, `02`, `05`, `09`) label or pin Pods to a specific
  node. If you run more than one of these back to back on the same
  cluster, re-check `kubectl get nodes --show-labels` between labs —
  each lab now uses its own label key (e.g. lab 01 uses
  `lab-relative-fawn`), so they shouldn't collide, but it's worth
  confirming on a shared cluster.
- Lab `10` directly edits `/etc/kubernetes/manifests/kube-apiserver.yaml`
  on a control-plane node and will make the apiserver briefly
  unreachable. Only run it on a cluster you can fully rebuild.
- `cleanup.sh` in each lab removes that lab's namespace/resources but
  won't undo cluster-wide installs (`metrics-server`, cert-manager, a
  NetworkPolicy-enforcing CNI) — remove those manually if you want a
  fully clean cluster again.
# cka-lab
