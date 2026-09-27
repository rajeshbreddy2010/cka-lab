## Hints
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
