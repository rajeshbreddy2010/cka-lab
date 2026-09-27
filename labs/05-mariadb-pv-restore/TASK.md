# Lab: Restore a deleted MariaDB Deployment with an existing PersistentVolume
(namespace `mariadb`)

## Scenario
A MariaDB Deployment in the `mariadb` namespace was deleted by mistake. The
underlying storage was provisioned with `reclaimPolicy: Retain`, so the data
still exists on a **PersistentVolume**, but the PersistentVolumeClaim and
Deployment are gone.

## Task
Restore the Deployment, ensuring data persistence:

1. Create a PersistentVolumeClaim named `mariadb` in the `mariadb` namespace:
   - Access mode `ReadWriteOnce`
   - Storage `250Mi`
   - **You must use the existing retained PersistentVolume.** Failure to do
     so will result in a reduced score. There is only one existing PV.
2. Edit the MariaDB Deployment file at `~/mariadb-deployment.yaml` to use the
   PVC you created, then apply it to the cluster.
3. Ensure the MariaDB Deployment is running and stable.

---
