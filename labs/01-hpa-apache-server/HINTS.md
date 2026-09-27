## Hints
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
