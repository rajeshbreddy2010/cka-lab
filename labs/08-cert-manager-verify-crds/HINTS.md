## Hints
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
