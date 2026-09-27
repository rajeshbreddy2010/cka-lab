## Hints
1. Start by reading, not applying: `cat ~/netpol/*.yaml` or open each file.
2. Find the backend's real container port:
   `kubectl get deploy backend -n backend -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'`
3. Find the backend's real Pod label:
   `kubectl get deploy backend -n backend -o jsonpath='{.spec.template.metadata.labels}'`
4. Find the frontend namespace's label that a `namespaceSelector` would
   match: `kubectl get ns frontend --show-labels`. Every namespace has the
   built-in `kubernetes.io/metadata.name=<namespace name>` label, which is
   the most reliable one to select on.
5. A policy that "works" isn't automatically correct — one of the samples
   allows all ingress from everywhere, which technically permits
   frontend-to-backend traffic too, but the task explicitly forbids being
   overly permissive.
6. A `podSelector` that doesn't match any real Pods' labels means the policy
   silently applies to zero Pods — check labels character-for-character.
7. Once you've picked the right file, apply just that one:
   `kubectl apply -f ~/netpol/<file>.yaml`. Don't edit or delete the others.

---
