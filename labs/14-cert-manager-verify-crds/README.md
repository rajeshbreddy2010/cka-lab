# Lab: Verify cert-manager and Extract CRD Documentation

## Scenario
cert-manager has already been deployed to your cluster. You need to confirm
it's healthy, then produce two reference files from `kubectl` output.

## Task
1. Verify the cert-manager application which has been deployed to your
   cluster.
2. Using `kubectl`, create a list of all cert-manager Custom Resource
   Definitions (CRDs) and save it to `~/resources.yaml`.
   - You **must** use `kubectl`'s default output format.
   - **Do not** set an output format (no `-o ...`).
   - Failure to comply will result in a reduced score.
3. Using `kubectl`, extract the documentation for the `subject`
   specification field of the `Certificate` Custom Resource and save it to
   `~/subject.yaml`.

---

## 1. Setup (run as instructor / before the exercise)

Installs the full cert-manager application (controller, webhook, cainjector)
so there's something real to verify — not just the CRDs on their own.

```bash
#!/usr/bin/env bash
set -euo pipefail

CM_VERSION=v1.15.3

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CM_VERSION}/cert-manager.yaml"

kubectl rollout status deploy/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deploy/cert-manager-webhook -n cert-manager --timeout=120s
kubectl rollout status deploy/cert-manager-cainjector -n cert-manager --timeout=120s

# Make sure the target files don't exist yet
rm -f ~/resources.yaml ~/subject.yaml

echo
echo "Setup complete. Check with:"
echo "  kubectl get pods -n cert-manager"
echo "  kubectl get crd | grep cert-manager"
```

**Expected starting state**

```bash
kubectl get pods -n cert-manager
# cert-manager-xxxxxxxxxx-xxxxx              1/1  Running
# cert-manager-cainjector-xxxxxxxxxx-xxxxx   1/1  Running
# cert-manager-webhook-xxxxxxxxxx-xxxxx      1/1  Running

ls ~/resources.yaml ~/subject.yaml
# No such file or directory (both, not created yet)
```

---

## 2. Hints (reveal one at a time)

1. "Verify the application" means checking that its Pods/Deployments are
   actually healthy, not just that it's installed — `kubectl get pods -n
   cert-manager` and `kubectl get deploy -n cert-manager` both matter.
2. CRDs are cluster-scoped: `kubectl get crd`, no `-n` needed.
3. cert-manager's CRDs all end in `cert-manager.io`, including the
   ACME-related ones under `acme.cert-manager.io` — `grep` for that suffix
   to catch all of them, not just ones with `cert-manager` in the name.
4. "Default output format" means the plain table `kubectl get` prints when
   you don't pass `-o` at all — not `-o wide`, not `-o name`, not `-o yaml`.
   Redirect that table straight to the file.
5. `kubectl explain <resource>.<field>` documents a field without needing
   the resource to exist — it reads the CRD's OpenAPI schema directly.
6. If `kubectl explain certificate.spec.subject` errors, confirm the exact
   resource name first: `kubectl api-resources | grep cert-manager`.

---

## 3. Solution

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

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash

echo "--- cert-manager health ---"
for d in cert-manager cert-manager-webhook cert-manager-cainjector; do
  ready=$(kubectl get deploy "$d" -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  desired=$(kubectl get deploy "$d" -n cert-manager -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" == "$desired" ]] \
    && echo "PASS: $d is healthy ($ready/$desired ready)" \
    || echo "FAIL: $d is not healthy (ready=${ready:-0}/$desired)"
done

echo
echo "--- resources.yaml ---"
if [[ -s ~/resources.yaml ]]; then
  n=$(grep -c "cert-manager.io" ~/resources.yaml)
  [[ "$n" -ge 6 ]] && echo "PASS: lists $n cert-manager CRDs" \
    || echo "FAIL: lists only $n (expected 6)"
  head -1 ~/resources.yaml | grep -qi '^NAME' \
    && echo "PASS: looks like default table output (has a NAME header)" \
    || echo "WARN: no NAME header found -- confirm no -o flag was used"
else
  echo "FAIL: ~/resources.yaml missing or empty"
fi

echo
echo "--- subject.yaml ---"
if [[ -s ~/subject.yaml ]]; then
  grep -qi "^FIELD:" ~/subject.yaml && grep -qi "subject" ~/subject.yaml \
    && echo "PASS: looks like 'kubectl explain certificate.spec.subject' output" \
    || echo "FAIL: content doesn't look like kubectl explain output"
else
  echo "FAIL: ~/subject.yaml missing or empty"
fi
```

Success criteria:

- All three cert-manager Deployments report ready replicas equal to desired.
- `~/resources.yaml` lists all 6 cert-manager CRDs, in `kubectl`'s default
  (non-`-o`) table format — recognizable by its `NAME` / `CREATED AT`
  header row.
- `~/subject.yaml` contains the `kubectl explain certificate.spec.subject`
  output (starts with a `FIELD:` / `DESCRIPTION:` block, mentions
  `cert-manager.io`).

---

## 5. Cleanup

```bash
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml
rm -f ~/resources.yaml ~/subject.yaml
```

## 6. Optional extensions

- Also verify the `cert-manager` webhook is reachable by creating a real
  `Certificate` (not just an `Issuer`) and watching it reach `Ready: True`.
- Document `certificate.spec.issuerRef` and `certificate.spec.dnsNames` the
  same way, into separate files.
- List CRDs with `kubectl get crd --show-labels` or
  `-o custom-columns=...` on a scratch file, purely to contrast against the
  required default-format file and reinforce why the flag mattered.
- Practice the same task against a different operator's CRDs (e.g.
  Prometheus Operator, external-dns) to generalize the pattern beyond
  cert-manager specifically.
