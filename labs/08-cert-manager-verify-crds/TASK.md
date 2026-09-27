# Lab: Verify cert-manager and Extract CRD Documentation

## Scenario
cert-manager has already been deployed to your cluster. You need to confirm
it's healthy, then produce two reference files from `kubectl` output.

## Task
1. Verify the cert-manager application which has been deployed to your
   cluster.
2. Using `kubectl`, create a list of all cert-manager Custom Resource
   Definitions (CRDs) and save it to `~/resources.yaml`.
   - You **must** use `kubectl`'s default output format.
   - **Do not** set an output format (no `-o ...`).
   - Failure to comply will result in a reduced score.
3. Using `kubectl`, extract the documentation for the `subject`
   specification field of the `Certificate` Custom Resource and save it to
   `~/subject.yaml`.

---
