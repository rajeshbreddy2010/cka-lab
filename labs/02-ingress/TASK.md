# Lab: Ingress Resource (CKA Question 12)

## Task
In namespace `sound-repeater`, for the existing Deployment `echo`:
1. Create Service `echoserver-service` (type NodePort, port 8080).
2. Create Ingress `echo` so `http://example.org/echo` reaches it.
3. Verify: `curl -o /dev/null -s -w "%{http_code}\n" http://example.org/echo` prints `200`.

## Run the lab
```bash
chmod +x *.sh
./setup.sh kind        # new kind cluster + ingress-nginx + Deployment (needs docker, kind, kubectl)
# or
./setup.sh existing    # use your current kubectl context (kubeadm, k3s, minikube...)
```
Now try it yourself before peeking at `solution.yaml`.

## Imperative hints (fast in the exam)
```bash
kubectl -n sound-repeater expose deploy echo --name=echoserver-service --port=8080 --target-port=8080 --type=NodePort
kubectl -n sound-repeater create ingress echo --class=nginx --rule="example.org/echo*=echoserver-service:8080"
```
(`/echo*` in `--rule` creates pathType Prefix.)

## Check / reset
```bash
./check.sh
./cleanup.sh
```

## Gotchas to practice
- Service selector must match pod labels (`app=echo`), otherwise no endpoints.
- `kubectl get ingressclass` — set `ingressClassName` to match.
- Use `pathType: Prefix` for `/echo`.
- `kubectl -n sound-repeater describe ingress echo` shows backends and events.
- On a non-kind cluster the ingress controller is on a NodePort, so plain `curl example.org` on port 80 won't work; see `setup.sh` output for the `--resolve` form.
