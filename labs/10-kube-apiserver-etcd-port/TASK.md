# Lab: Broken kube-apiserver After an etcd Migration (wrong etcd port)

## Scenario
After a cluster migration, the control plane's `kube-apiserver` is not
coming up. Before the migration, etcd was **external** and running in HA.
After the migration, the kube-apiserver's manifest was left pointing at
etcd's **peer port (2380)** instead of its **client port (2379)**.

## Task
Fix it. `kube-apiserver` must come back up and the cluster must become
healthy again.

---

## 0. Prerequisites

This is a **kubeadm-style static-Pod** scenario — it requires root/SSH
access to the control plane node's filesystem (`/etc/kubernetes/manifests`),
not just a `kubectl` connection (which won't work anyway once the apiserver
is down). It also assumes an **external** etcd cluster already configured
in `kube-apiserver`'s manifest (`--etcd-servers=https://<ip>:2379,...`), as
described in the scenario. If your practice cluster uses kubeadm's default
**stacked** (local) etcd instead, adapt the setup script's `sed` target to
match your actual `--etcd-servers` value first.

---
