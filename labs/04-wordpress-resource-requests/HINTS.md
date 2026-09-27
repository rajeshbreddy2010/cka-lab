## Hints
1. `kubectl describe node <node>` shows **Allocatable** and **Allocated resources**.
2. Other Pods on the node (kube-system, CNI, etc.) already reserve some
   requests. Only the *free* amount can be shared.
3. The scheduler uses the *effective* Pod request: the larger of
   (highest single init container, since they run one after another) and
   (sum of app containers). Set every container the same, otherwise one
   leftover high value keeps the Pods Pending.
   Note that `init-setup` already looks fine (250m / 500Mi) but is a trap in
   the other direction: its limits (500m / 1000Mi) cap what you can request.
4. Scaling to 0 first makes the "Allocated resources" figure clean:
   `kubectl scale deploy wordpress -n relative-fawn --replicas=0`

---
