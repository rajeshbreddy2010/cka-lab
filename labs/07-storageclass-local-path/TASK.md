# Lab: StorageClass for an Existing Provisioner

## Task
First, create a new StorageClass named `local-path` for an existing
provisioner named `rancher.io/local-path`.

Set the volume binding mode to `WaitForFirstConsumer`. Not setting the
volume binding mode, or setting it to anything other than
`WaitForFirstConsumer`, may result in a reduced score.

Next, configure the StorageClass `local-path` as the default StorageClass.

Do not modify any existing Deployments or PersistentVolumeClaims. Failure
to do so may result in a reduced score.

## How this differs from the other StorageClass lab
This one is the mirror image of the `local-storage` lab:
- Here the **controller is already running** but has **no StorageClass
  object** pointing at it — you create `local-path` from scratch.
- There is no second class to un-default; `local-path` just needs to end
  up as the default.
- The name you create here — `local-path` — matches the provisioner's
  usual/default class name, which is a deliberate way of testing whether
  you read "create a new StorageClass named X" carefully rather than
  assuming X is already there because the provisioner is running.

## Run
```bash
chmod +x *.sh
./setup.sh      # installs the local-path-provisioner controller, deletes any StorageClass it ships with
```
Check the starting state before you touch anything:
```bash
kubectl get sc                 # should be empty
kubectl get pods -n local-path-storage   # controller is running
```
Do the task yourself, then `./check.sh`. `solution.sh` has the answer.

## Key commands
```bash
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
YAML

kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Gotchas
- `volumeBindingMode` is immutable — get it wrong and you must delete and
  recreate the StorageClass, not patch it.
- The provisioner being "existing" only means the **controller Pod** is
  already running; it does not mean a StorageClass already exists for it.
  Don't assume one does — check with `kubectl get sc` first.
- "Do not modify existing Deployments or PVCs" — the lab's `data-app`
  Deployment and `data-pvc` PVC are bound via a manually-created PV, not
  through any StorageClass, so they're unaffected by whatever you do here.
  `check.sh` confirms they're untouched either way.
- If `kubectl get sc` shows more than one `(default)` after you're done,
  you've got a second default somewhere — un-default it the same way as
  the other lab.
