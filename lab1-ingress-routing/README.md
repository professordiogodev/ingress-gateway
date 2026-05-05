# Lab 1 — Ingress: Path & Subdomain Routing

## Before this lab

Make sure you've run all six scripts in [`setup/`](../setup/README.md). You need:
- NGINX Ingress Controller running in your cluster
- external-dns running and able to create Route53 records
- `STUDENT_NAME` exported in your shell

```bash
# Verify the controller is ready
kubectl get pods -n ingress-nginx
kubectl get pods -n external-dns

# Set your name if you haven't already
export STUDENT_NAME=yourname
```

---

## What is this lab about?

You'll expose two applications to the internet using a single **Kubernetes Ingress** resource — without creating a load balancer per app. You'll practice two routing strategies:

- **Path-based routing**: one hostname, different URL paths go to different apps
- **Host-based (subdomain) routing**: different subdomains go to different apps

By the end, both of these will work from any browser:

```
http://YOURNAME.eks.ironlabs.online/blue   → Blue app
http://YOURNAME.eks.ironlabs.online/green  → Green app
http://blue.YOURNAME.eks.ironlabs.online   → Blue app
http://green.YOURNAME.eks.ironlabs.online  → Green app
```

---

## Concepts

### The problem Ingress solves

Without Ingress, exposing an application requires a **Service of type `LoadBalancer`**. In AWS that creates one Network Load Balancer per service — roughly $20/month each. Ten microservices means ten load balancers and a $200/month networking bill before you've written a line of code.

**Ingress** fixes this: a single NLB feeds a single **Ingress Controller** (NGINX in this case), which acts as a reverse proxy and routes incoming requests to the right Service based on hostname and path. One load balancer, as many apps as you like.

```
Internet
   │
   ▼
[NLB] ← one load balancer for your whole cluster
   │
   ▼
[NGINX Ingress Controller pod]
   │ reads your Ingress resources and routes accordingly
   ├── host: YOURNAME.eks.ironlabs.online, path /blue  ──▶ app-blue Service
   ├── host: YOURNAME.eks.ironlabs.online, path /green ──▶ app-green Service
   ├── host: blue.YOURNAME.eks.ironlabs.online         ──▶ app-blue Service
   └── host: green.YOURNAME.eks.ironlabs.online        ──▶ app-green Service
```

### Key terms

| Term | What it is |
|------|-----------|
| **Ingress** | A Kubernetes resource (YAML) describing routing rules |
| **IngressClass** | Tells Kubernetes which controller handles this Ingress (`nginx` here) |
| **Ingress Controller** | The NGINX pod that reads Ingress resources and proxies traffic |
| **external-dns** | Watches your Ingress resources and auto-creates Route53 DNS records |

### Why `ingressClassName: nginx`?

A cluster can run multiple Ingress Controllers (e.g. one for internal traffic, one for external). The `ingressClassName` field is how you say "this NGINX controller should handle this Ingress." If you omit it, the cluster's default IngressClass is used (if one is configured).

---

## Step-by-step

### Step 1 — Set your name

```bash
# Lowercase, no spaces, no dots — becomes your DNS subdomain
export STUDENT_NAME=yourname
```

Run this in every terminal tab you open for this lab.

---

### Step 2 — Deploy the two apps

```bash
kubectl apply -f apps.yaml
```

This creates the `lab1` namespace, two nginx Deployments, two Services, and two ConfigMaps that supply the HTML. No `envsubst` needed here — the namespace is hardcoded as `lab1`.

Verify:

```bash
kubectl get pods -n lab1
# Both pods should reach Running state within ~30 seconds
```

The YAML for the apps looks like this (already in `apps.yaml`):

```yaml
# ─── ConfigMap: supplies the HTML page the blue nginx serves ──────────────────
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-blue-html
  namespace: lab1   # hardcoded — it's your cluster, no isolation needed
data:
  index.html: |
    <html>... blue page ...</html>
---
# ─── Deployment: runs nginx with the blue HTML mounted in ────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
  namespace: lab1
spec:
  replicas: 1
  ...
---
# ─── Service: ClusterIP — internal only, the Ingress Controller will use this ─
# No LoadBalancer here. The whole point of Ingress is that the controller
# forwards traffic to ClusterIP services internally.
apiVersion: v1
kind: Service
metadata:
  name: app-blue
  namespace: lab1
spec:
  selector:
    app: app-blue
  ports:
    - port: 80
      targetPort: 80
```

---

### Step 3 — Create the Ingress resources

The Ingress YAML uses `${STUDENT_NAME}` in the hostnames, so you need `envsubst`:

```bash
envsubst < ingress.yaml | kubectl apply -f -
```

The Ingress YAML (already in `ingress.yaml`):

```yaml
# ─── Ingress 1: PATH-BASED ────────────────────────────────────────────────────
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-routing
  namespace: lab1
  annotations:
    # Strip the path prefix before forwarding to the backend.
    # Without this, /blue is forwarded as /blue but nginx only serves /.
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx    # must match the IngressClass in your cluster
  rules:
    - host: YOUR_STUDENT_NAME.eks.ironlabs.online
      http:
        paths:
          - path: /blue
            pathType: Prefix
            backend:
              service:
                name: app-blue
                port:
                  number: 80
          - path: /green
            pathType: Prefix
            backend:
              service:
                name: app-green
                port:
                  number: 80
---
# ─── Ingress 2: HOST-BASED (subdomain) ────────────────────────────────────────
# Different hostnames in spec.rules[] → different backends.
# No rewrite needed: the root / goes directly to the app.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: subdomain-routing
  namespace: lab1
spec:
  ingressClassName: nginx
  rules:
    - host: blue.YOUR_STUDENT_NAME.eks.ironlabs.online
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-blue
                port:
                  number: 80
    - host: green.YOUR_STUDENT_NAME.eks.ironlabs.online
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-green
                port:
                  number: 80
```

Check the Ingress objects were created and have an address:

```bash
kubectl get ingress -n lab1
# The ADDRESS column fills in with your NLB hostname.
# external-dns picks up the hostnames in spec.rules and creates DNS records.
```

---

### Step 4 — Wait for DNS propagation

external-dns detects the new Ingress and creates CNAME records in Route53. This takes about 60–90 seconds.

```bash
# Poll until your record resolves
watch -n5 "nslookup ${STUDENT_NAME}.eks.ironlabs.online"
```

You'll know it's ready when you see an IP address (or the NLB hostname) in the answer section.

---

### Step 5 — Test path-based routing

```bash
curl http://${STUDENT_NAME}.eks.ironlabs.online/blue
curl http://${STUDENT_NAME}.eks.ironlabs.online/green
```

Open in a browser — you'll see a blue or green colored page.

---

### Step 6 — Test subdomain routing

```bash
curl http://blue.${STUDENT_NAME}.eks.ironlabs.online
curl http://green.${STUDENT_NAME}.eks.ironlabs.online
```

---

## What happened under the hood

1. You applied two `Ingress` resources with `ingressClassName: nginx`
2. The NGINX Ingress Controller detected them and updated its internal `nginx.conf` with new `server {}` blocks for your hostnames
3. external-dns detected the hostnames in `spec.rules[].host` and called Route53 to create CNAME records pointing at your NLB
4. Traffic: `browser → Route53 CNAME → NLB → NGINX pod → app-blue or app-green pod`

### Bonus: See the generated NGINX config

```bash
NGINX_POD=$(kubectl get pod -n ingress-nginx \
  -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n ingress-nginx $NGINX_POD -- \
  nginx -T 2>/dev/null | grep -A 20 "server_name.*${STUDENT_NAME}"
```

You'll see the `server {}` blocks NGINX generated from your Ingress rules.

---

## Clean up

```bash
envsubst < ingress.yaml | kubectl delete -f -
kubectl delete -f apps.yaml
```

This removes the Ingress resources, apps, and the `lab1` namespace. external-dns detects the deleted Ingress and removes the Route53 DNS records within a minute or two.

---

## Key takeaways

- **Ingress** is a routing layer — one load balancer, many apps
- **IngressClass** tells Kubernetes which controller handles a given Ingress
- **Path routing** needs `rewrite-target` to strip the prefix before forwarding
- **Host routing** needs distinct values in `spec.rules[].host` — the controller reads the `Host` header
- **external-dns** makes DNS automatic — hostnames in your Ingress become Route53 records with no manual work

When you're done, continue to [Lab 2 →](../lab2-ingress-https/README.md)
