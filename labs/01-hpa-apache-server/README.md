# Lab: HorizontalPodAutoscaler for `apache-server` (namespace `autoscale`)

## Scenario
The `apache-server` Deployment in the `autoscale` namespace needs to scale
automatically based on CPU usage.

## Task
Create a new HorizontalPodAutoscaler (HPA) named `apache-server` in the
`autoscale` namespace. This HPA must target the existing Deployment called
`apache-server` in the `autoscale` namespace.

Set the HPA to aim for **50% CPU usage per Pod**. Configure it to have **at
least 1 Pod and no more than 4 Pods**. Also, set the **downscale
stabilization window to 30 seconds**.

---

## 0. Prerequisite: metrics-server

An HPA needs CPU/memory metrics from the **Metrics API**, which
`metrics-server` provides. Without it, the HPA object can be created but
will show `<unknown>` for `TARGETS` forever and never actually scale.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# On kind/minikube/self-signed kubelet certs, metrics-server needs this flag,
# otherwise it can't scrape kubelets:
kubectl patch deployment metrics-server -n kube-system --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}
]'

kubectl rollout status deploy/metrics-server -n kube-system --timeout=90s
kubectl top nodes   # should return numbers, not an error, once it's ready (can take ~1 min)
```

---

## 1. Setup (run as instructor / before the exercise)

The Deployment **must have a CPU `request`** set on its container — the HPA
computes "% of CPU usage" relative to the request, and without one the HPA
can be created but will never compute a usable percentage.

```bash
#!/usr/bin/env bash
set -euo pipefail

NS=autoscale

kubectl delete namespace "$NS" --ignore-not-found --wait=true
kubectl create namespace "$NS"

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-server
  namespace: $NS
  labels:
    app: apache-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apache-server
  template:
    metadata:
      labels:
        app: apache-server
    spec:
      containers:
      - name: apache-server
        image: httpd:2.4
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF

kubectl rollout status deploy/apache-server -n "$NS" --timeout=60s

echo
echo "Setup complete."
echo "  kubectl get deploy apache-server -n $NS"
echo "  kubectl get hpa -n $NS   # should show none yet"
```

**Expected starting state**

```bash
kubectl get deploy apache-server -n autoscale
# 1/1 ready

kubectl get hpa -n autoscale
# No resources found
```

---

## 2. Hints (reveal one at a time)

1. `kubectl autoscale deployment apache-server -n autoscale --cpu-percent=50
   --min=1 --max=4` creates the HPA quickly, but `kubectl autoscale` has
   **no flag for the stabilization window** — you'll need to patch or edit
   the object afterward (or write the YAML directly).
2. The stabilization window belongs under `spec.behavior.scaleDown`, only
   available on `autoscaling/v2` (not the older `v1` API).
3. `kubectl get hpa apache-server -n autoscale` showing `TARGETS: <unknown>/50%`
   almost always means metrics-server isn't installed/ready yet, not that
   your HPA spec is wrong.
4. `averageUtilization: 50` is a percentage of the container's CPU
   **request**, not an absolute CPU value — confirm the Deployment actually
   has a CPU request set.
5. `minReplicas: 1`, `maxReplicas: 4` map directly to "at least 1 Pod and no
   more than 4 Pods."

---

## 3. Solution

### Quick path, then patch
```bash
kubectl autoscale deployment apache-server -n autoscale \
  --cpu-percent=50 --min=1 --max=4
```

Add the stabilization window (not settable via `kubectl autoscale`):

```bash
kubectl patch hpa apache-server -n autoscale --type=merge -p '
{
  "spec": {
    "behavior": {
      "scaleDown": {
        "stabilizationWindowSeconds": 30
      }
    }
  }
}'
```

### Or, fully declarative
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: apache-server
  namespace: autoscale
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: apache-server
  minReplicas: 1
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
```

```bash
kubectl apply -f apache-server-hpa.yaml
```

### Verify
```bash
kubectl get hpa apache-server -n autoscale
# NAME            REFERENCE                  TARGETS   MINPODS   MAXPODS   REPLICAS
# apache-server   Deployment/apache-server   <X>%/50%  1         4         1

kubectl get hpa apache-server -n autoscale -o yaml | grep -A3 behavior
```

Once metrics-server has scraped at least one cycle, `TARGETS` shows a real
percentage instead of `<unknown>`.

Optional: generate load to watch it actually scale up:
```bash
kubectl run load-gen --rm -it --restart=Never --image=busybox:stable -n autoscale -- \
  sh -c "while true; do wget -q -O- http://apache-server; done"
```
then in another terminal:
```bash
kubectl get hpa apache-server -n autoscale -w
```

---

## 4. Verification / checker

Save as `check.sh`:

```bash
#!/usr/bin/env bash
NS=autoscale

target=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null)
kind=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.scaleTargetRef.kind}' 2>/dev/null)
[[ "$target" == "apache-server" && "$kind" == "Deployment" ]] \
  && echo "PASS: HPA targets Deployment/apache-server" \
  || echo "FAIL: HPA targets $kind/$target"

minr=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.minReplicas}')
maxr=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.maxReplicas}')
[[ "$minr" == "1" && "$maxr" == "4" ]] \
  && echo "PASS: minReplicas=1, maxReplicas=4" \
  || echo "FAIL: minReplicas=$minr maxReplicas=$maxr"

util=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}')
[[ "$util" == "50" ]] && echo "PASS: CPU target is 50%" || echo "FAIL: CPU target is '${util:-unset}'"

window=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}')
[[ "$window" == "30" ]] && echo "PASS: downscale stabilization window is 30s" \
  || echo "FAIL: stabilization window is '${window:-unset}'"

req=$(kubectl get deploy apache-server -n $NS -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
[[ -n "$req" ]] && echo "PASS: apache-server container has a CPU request ($req), so % utilization is meaningful" \
  || echo "FAIL: apache-server container has no CPU request set"

cur=$(kubectl get hpa apache-server -n $NS -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
[[ -n "$cur" ]] && echo "PASS: metrics-server is reporting a current value ($cur%)" \
  || echo "WARN: current utilization not reported yet -- check metrics-server is installed and has scraped at least once"
```

Success criteria:

- HPA named `apache-server` exists in `autoscale`, targeting
  `Deployment/apache-server`.
- `minReplicas: 1`, `maxReplicas: 4`.
- CPU target: `Utilization`, `averageUtilization: 50`.
- `spec.behavior.scaleDown.stabilizationWindowSeconds: 30`.
- `status.currentMetrics` eventually shows a real number (proves
  metrics-server is wired up correctly), not `<unknown>`.

---

## 5. Cleanup
```bash
kubectl delete namespace autoscale
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## 6. Optional extensions

- Add a memory-based metric alongside CPU and observe how the HPA picks the
  metric that recommends the highest replica count.
- Set `behavior.scaleUp.stabilizationWindowSeconds: 0` and
  `policies` with a `Pods` type to scale up fast but down slow, and discuss
  why that asymmetry is common in production.
- Lower `maxReplicas` to 2 and generate load, to see the HPA cap itself
  even under sustained pressure.
- Swap the CPU metric for a custom metric (e.g. via Prometheus Adapter) to
  discuss `autoscaling/v2`'s support for `Pods`, `Object`, and `External`
  metric types beyond just `Resource`.
