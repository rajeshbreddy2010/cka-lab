## Hints
1. `kubectl get pv mariadb-pv -o yaml` shows `status.phase: Released` and a
   `spec.claimRef` still pointing at the old, now-deleted PVC.
2. A `Released` PV is **not** automatically reusable. A brand-new PVC that
   matches capacity/accessMode/storageClassName perfectly will still stay
   `Pending` if the PV's `claimRef` points somewhere else (or to something
   that no longer exists) — the claimRef is checked, not just the specs.
3. To make the PV `Available` again for a new claim, remove its `claimRef`:
   `kubectl patch pv mariadb-pv -p '{"spec":{"claimRef": null}}'`, or edit /
   `replace` the PV's YAML with the `claimRef:` block deleted. Note that
   `kubectl apply` alone won't clear it — `apply` only touches fields it
   previously managed, and `claimRef` was set by the binding controller.
4. The PVC must request the same `storageClassName` as the PV (`manual`
   here) — a PVC with no storage class, or a different one, may bind to a
   different (or no) PV depending on your default StorageClass.
5. To pin the new PVC to *this specific* PV, either clear the claimRef and
   let matching specs bind them, or set `spec.volumeName: mariadb-pv`
   explicitly on the PVC to force it.
6. `250Mi` in the PVC must be `<=` the PV's capacity (`250Mi`) — requesting
   more than the PV offers will leave the PVC unbound forever, since there's
   only one PV to bind against.
7. The Deployment file has a `volumeMounts` entry named `data` but no
   `volumes:` section yet — add it under `spec.template.spec.volumes`,
   referencing your new PVC by name (`mariadb`).

---
