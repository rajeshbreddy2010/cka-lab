## Solution
### Step 1: add containerPort 80 to the nginx container

```bash
kubectl patch deployment front-end -n spline-reticulator --type=json -p='[
 {"op":"add","path":"/spec/template/spec/containers/0/ports","value":[{"containerPort":80,"protocol":"TCP"}]}
]'
```

Or `kubectl edit deploy front-end -n spline-reticulator` and add under the
`nginx` container:

```yaml
        ports:
        - containerPort: 80
          protocol: TCP
```

### Step 2: create the Service

Quickest way — generate it from the Deployment, then rename/retype:

```bash
kubectl expose deployment front-end -n spline-reticulator \
  --name=front-end-svc \
  --port=80 \
  --target-port=80 \
  --type=NodePort
```

Or declaratively:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: front-end-svc
  namespace: spline-reticulator
spec:
  type: NodePort
  selector:
    app: front-end
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
```

```bash
kubectl apply -f front-end-svc.yaml
```

### Step 3: verify

```bash
kubectl get svc front-end-svc -n spline-reticulator
# TYPE=NodePort, PORT(S)=80:3XXXX/TCP

kubectl get endpoints front-end-svc -n spline-reticulator
# should list 2 Pod IPs on port 80
```

Test from inside the cluster or from a node:

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc front-end-svc -n spline-reticulator -o jsonpath='{.spec.ports[0].nodePort}')
curl -s -o /dev/null -w "%{http_code}\n" "http://$NODE_IP:$NODE_PORT"
# 200
```

---
