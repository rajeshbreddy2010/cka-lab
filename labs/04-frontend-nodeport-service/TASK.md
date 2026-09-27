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
