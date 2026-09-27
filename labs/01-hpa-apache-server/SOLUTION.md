## Solution
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
