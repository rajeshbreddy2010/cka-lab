# Lab: Fix WordPress Pods stuck in Pending (namespace `relative-fawn`)

## Scenario
You manage a WordPress application. Some Pods are not starting because their
resource requests are too high.

## Task
The WordPress application in the `relative-fawn` namespace consists of a
`wordpress` Deployment with **3 replicas**.

Adjust **all Pod resource requests** as follows:

- Divide the node's resources evenly across all 3 Pods.
- Give each Pod a fair share of CPU and memory.
- Use the same requests for the init container (`init-setup`) and the main
  container (`wordpress`).
- A request can never exceed its limit. `init-setup` has limits of 500m CPU /
  1000Mi memory; if your new request is higher, raise the limit to match.
- Leave a small safety margin (about 10-15%) so the node is not 100% committed.

You may need to scale the Deployment down first while you edit it.

---
