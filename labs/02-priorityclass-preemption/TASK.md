# Lab: PriorityClass and Pod preemption (namespace `priority`)

## Scenario
The `priority` namespace runs several workloads on a node that is almost
full. The `busybox-logger` Deployment is important and cannot get all of its
Pods scheduled. You need to give it a higher priority than the other workloads.

## Task
1. Create a new PriorityClass named `high-priority` for user workloads with a
   value that is **one less than the highest existing user-defined**
   PriorityClass value.
2. Patch the existing Deployment `busybox-logger` running in the `priority`
   namespace to use the `high-priority` PriorityClass.
3. Ensure that the `busybox-logger` Deployment rolls out successfully with the
   new PriorityClass set.

It is expected that Pods from other Deployments running in the `priority`
namespace are evicted.

**Do not modify other Deployments running in the `priority` namespace.**
Failure to do so may result in a reduced score.

---
