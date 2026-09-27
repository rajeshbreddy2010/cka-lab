# Lab: StorageClass (CKA Question 14)

## Task
1. Create StorageClass `local-storage`, provisioner `rancher.io/local-path`,
   `volumeBindingMode: WaitForFirstConsumer`, NOT default at creation.
2. Patch it to become the default StorageClass.
3. Make sure `local-storage` is the ONLY default class.
4. Do not modify existing Deployments or PVCs.

## Run
```bash
chmod +x *.sh
./setup.sh      # ensures local-path-provisioner, makes "local-path" the default, creates existing PVC + Deployment
```
Try it yourself, then `./verify.sh`. `solution.sh` has the answer.

## Key commands
```bash
kubectl get sc                                   # "(default)" marks the default
kubectl patch sc local-storage -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch sc local-path    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

## Prove it works (optional)
```bash
kubectl create ns test-default
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: t, namespace: test-default}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 50Mi}}
YAML
kubectl -n test-default get pvc t -o jsonpath='{.spec.storageClassName}{"\n"}'   # local-storage
kubectl -n test-default get pvc t   # Pending is expected until a pod uses it (WaitForFirstConsumer)
```

## Gotchas
- `volumeBindingMode` is immutable: get it wrong and you must delete and recreate the SC.
- Two defaults is a real failure mode; PVCs without a class then get ambiguous behavior.
- Existing PVCs keep the class they were created with; changing the default never rewrites them.
- Setting the annotation to "false" (or removing it) both un-default a class.
