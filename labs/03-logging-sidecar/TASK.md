# Lab: Streaming Sidecar Containers for Logging

Two related tasks: adding a log-streaming sidecar to a **Deployment** and to a
bare **Pod**. Both use the same pattern — a shared `emptyDir` Volume mounted
at `/var/log`, with a `busybox` sidecar tailing the log file so
`kubectl logs <pod> -c sidecar` exposes it through the normal logging
pipeline.

---

## Task A — Deployment `synergy-leverager` (namespace `default`, or as set up)

Update the existing Deployment `synergy-leverager`, adding a co-located
container named `sidecar` using the `busybox:stable` image to the existing
Pod. The new co-located container has to run the following command:

```
/bin/sh -c "tail -n+1 -f /var/log/synergy-leverager.log"
```

Use a Volume mounted at `/var/log` to make the log file
`synergy-leverager.log` available to the co-located container.

**Do not modify the specification of the existing container other than
adding the required volume mount.**

## Task B — bare Pod `big-corp-app`

An existing Pod needs to be integrated into the Kubernetes built-in logging
architecture (e.g. `kubectl logs`). Adding a streaming sidecar container is a
good and common way to accomplish this requirement.

Add a sidecar container named `sidecar`, using the `busybox` image, to the
existing Pod `big-corp-app`. The new sidecar container has to run the
following command:

```
/bin/sh -c tail -n+1 -f /var/log/big-corp-app.log
```

Use a Volume, mounted at `/var/log`, to make the log file
`big-corp-app.log` available to the sidecar container.

---
