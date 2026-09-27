# Lab: Expose a Deployment via a NodePort Service (namespace `spline-reticulator`)

## Scenario
The `front-end` Deployment runs an `nginx` container, but its port is not
declared on the container, and there's no Service in front of it yet.

## Task
Reconfigure the existing Deployment `front-end` in namespace
`spline-reticulator` to expose port `80/tcp` of the existing container
`nginx`.

Create a new Service named `front-end-svc` exposing the container port
`80/tcp`.

Configure the new Service to also expose the individual Pods via a
**NodePort**.

---

## 1. Setup (run as instructor / before the exercise)

```bash
#!/usr/bin/env bash
set -euo pipefail

NS=spline-reticulator

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: front-end
  namespace: $NS
  labels:
    app: front-end
spec:
  replicas: 2
  selector:
    matchLabels:
      app: front-end
  template:
    metadata:
      labels:
        app: front-end
    spec:
      containers:
      - name: nginx
        image: nginx:stable
EOF

kubectl rollout status deploy/front-end -n "$NS" --timeout=60s

echo
echo "Done. Deployment 'front-end' has no containerPort declared and no Service yet:"
echo "  kubectl get deploy front-end -n $NS -o yaml | grep -A3 containers:"
echo "  kubectl get svc -n $NS"
```

**Expected starting state**

```bash
kubectl get deploy front-end -n spline-reticulator -o yaml
# containers[0] has no 'ports:' field at all

kubectl get svc -n spline-reticulator
# No resources found
```

---

## 2. Hints (reveal one at a time)

1. `containerPort` is documentation for humans/tools (kubectl, other
   controllers); it doesn't change what the container actually listens on,
   but the task explicitly asks for it, so add it.
2. `kubectl expose deployment ...` is the fastest way to create a Service
   from an existing Deployment's Pod labels and port.
3. A NodePort Service's `spec.ports[].port` is the Service's own
   cluster-internal port; `targetPort` is the container port; `nodePort` is
   the port opened on every node. If you don't set `nodePort`, Kubernetes
   picks one for you from the default range (30000-32767).
4. `type: NodePort` implies the Service is also reachable on its
   `ClusterIP:port` inside the cluster — a NodePort Service isn't
   NodePort-only, it's a superset of `ClusterIP`.
5. The Service's `selector` must match the Deployment Pod template's labels
   (`app: front-end` here), or it won't route to any Pods.

---

## 3. Solution

### Step 1: add containerPort 80 to the nginx container

```bash
kubectl patch deployment front-end -n spline-reticulator --type=json -p='[
 {"op":"add","path":"/spec/template/spec/containers/0/ports","value":[{"containerPort":80,"protocol":"TCP"}]}
]'
```

Or `kubectl edit deploy front-end -n spline-reticulator` and add under the
`nginx` container:

```yaml
        ports:
        - containerPort: 80
          protocol: TCP
```

### Step 2: create the Service

Quickest way — generate it from the Deployment, then rename/retype:

```bash
kubectl expose deployment front-end -n spline-reticulator \
  --name=front-end-svc \
  --port=80 \
  --target-port=80 \
  --type=NodePort
```

Or declaratively:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: front-end-svc
  namespace: spline-reticulator
spec:
  type: NodePort
  selector:
    app: front-end
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
```

```bash
kubectl apply -f front-end-svc.yaml
```

### Step 3: verify

```bash
kubectl get svc front-end-svc -n spline-reticulator
# TYPE=NodePort, PORT(S)=80:3XXXX/TCP

kubectl get endpoints front-end-svc -n spline-reticulator
# should list 2 Pod IPs on port 80
```

Test from inside the cluster or from a node:

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc front-end-svc -n spline-reticulator -o jsonpath='{.spec.ports[0].nodePort}')
curl -s -o /dev/null -w "%{http_code}\n" "http://$NODE_IP:$NODE_PORT"
# 200
```

---

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash
NS=spline-reticulator

cp=$(kubectl get deploy front-end -n $NS -o jsonpath='{.spec.template.spec.containers[?(@.name=="nginx")].ports[0].containerPort}')
[[ "$cp" == "80" ]] && echo "PASS: nginx container declares containerPort 80" \
  || echo "FAIL: nginx containerPort is '${cp:-unset}'"

svc_type=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.type}' 2>/dev/null)
[[ "$svc_type" == "NodePort" ]] && echo "PASS: front-end-svc is type NodePort" \
  || echo "FAIL: front-end-svc type is '${svc_type:-missing}'"

port=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.ports[0].port}')
tport=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.ports[0].targetPort}')
nport=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.ports[0].nodePort}')
[[ "$port" == "80" && "$tport" == "80" ]] && echo "PASS: Service port/targetPort are 80/80" \
  || echo "FAIL: Service port=$port targetPort=$tport"
[[ -n "$nport" && "$nport" -ge 30000 && "$nport" -le 32767 ]] 2>/dev/null \
  && echo "PASS: nodePort $nport is allocated" || echo "FAIL: nodePort missing or out of range"

sel=$(kubectl get svc front-end-svc -n $NS -o jsonpath='{.spec.selector.app}')
[[ "$sel" == "front-end" ]] && echo "PASS: selector matches Deployment Pods" \
  || echo "FAIL: selector is '${sel:-missing}'"

eps=$(kubectl get endpoints front-end-svc -n $NS -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
[[ "$eps" -ge 1 ]] && echo "PASS: Service has $eps endpoint(s)" \
  || echo "FAIL: no endpoints — check selector/labels/readiness"
```

Success criteria:

- `front-end`'s `nginx` container declares `containerPort: 80`.
- Service `front-end-svc` exists, `type: NodePort`, `port: 80`,
  `targetPort: 80`, and has a `nodePort` allocated in the 30000-32767 range
  (or whatever your cluster's configured range is).
- The Service has live endpoints matching the `front-end` Pods.

---

## 5. Cleanup

```bash
kubectl delete namespace spline-reticulator
```

## 6. Optional extensions

- Pin an explicit `nodePort` (e.g. `30080`) instead of letting Kubernetes
  choose one, and note the valid range constraint.
- Add a second container port (e.g. a metrics port) and a second Service
  port, and practice naming ports (`name: http`, `name: metrics`) since a
  Service with more than one port requires named ports.
- Convert the Service to `type: LoadBalancer` (on a cloud/kind-with-
  cloud-provider setup) and compare behavior with `NodePort`.
- Scale the Deployment to 4 replicas and confirm the Service load-balances
  across all of them via `kubectl get endpoints`.
