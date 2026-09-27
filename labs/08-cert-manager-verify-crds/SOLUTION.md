## Solution
### Step 1: verify the application

```bash
kubectl get pods -n cert-manager
kubectl get deploy -n cert-manager
```

All three Deployments (`cert-manager`, `cert-manager-webhook`,
`cert-manager-cainjector`) should show `READY` matching `AVAILABLE`
(e.g. `1/1`), and every Pod should be `Running` with no restarts. A quick
functional check — create a self-signed `Issuer` and confirm it becomes
`Ready`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-check
  namespace: default
spec:
  selfSigned: {}
EOF

kubectl get issuer selfsigned-check -n default
# READY = True

kubectl delete issuer selfsigned-check -n default
```

### Step 2: list the CRDs with the default output format

```bash
kubectl get crd | grep cert-manager > ~/resources.yaml
```

Do **not** add `-o name`, `-o yaml`, `-o wide`, etc. — the task specifically
requires the default table format, so `~/resources.yaml` will contain
column output (`NAME`, `CREATED AT`), not YAML, despite the `.yaml`
extension. That mismatch between filename and content is intentional in the
task and expected.

Verify:
```bash
cat ~/resources.yaml
```
Should list all 6:
```
certificaterequests.cert-manager.io
certificates.cert-manager.io
challenges.acme.cert-manager.io
clusterissuers.cert-manager.io
issuers.cert-manager.io
orders.acme.cert-manager.io
```
(with `CREATED AT` timestamps alongside each, since that's the default
table's second column for CRDs).

### Step 3: extract the `subject` field documentation

```bash
kubectl explain certificate.spec.subject > ~/subject.yaml
```

Confirm it landed correctly:
```bash
cat ~/subject.yaml
```

---
