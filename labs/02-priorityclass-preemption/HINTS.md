## Hints
1. `kubectl get priorityclass` lists them all, `--sort-by=.value` orders them.
2. The `system-cluster-critical` and `system-node-critical` classes are
   **not** user-defined. Ignore them when finding the highest value.
3. PriorityClass is cluster-scoped, so there is no `-n`.
4. `kubectl create priorityclass --help` shows the flags.
5. The class goes in the **Pod template**: `spec.template.spec.priorityClassName`,
   not at the Deployment's top level.
6. The scheduler preempts (evicts) lower-priority Pods to make room for a
   higher-priority Pod that cannot be scheduled. You don't need to delete
   anything yourself.

---
