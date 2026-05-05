# Lab 1 — Ingress: Path & Subdomain Routing

## What is this lab about?

You'll expose two applications to the internet using a single **Kubernetes Ingress** resource. You'll learn two different routing strategies:
- **Path-based routing**: one hostname, different URL paths go to different apps
- **Host-based (subdomain) routing**: different hostnames go to different apps

Your apps will be reachable at:
- `http://YOURNAME.eks.ironlabs.online/blue` → Blue app
- `http://YOURNAME.eks.ironlabs.online/green` → Green app
- `http://blue.YOURNAME.eks.ironlabs.online` → Blue app
- `http://green.YOURNAME.eks.ironlabs.online` → Green app

---

## Concepts you need to know

### The problem: one LoadBalancer per app doesn't scale

Without Ingress, exposing an application requires a **Service of type `LoadBalancer`**. On AWS, each LoadBalancer service provisions a new Network Load Balancer (NLB) — at ~$20/month each. For 50 microservices that's $1,000/month just in load balancers.

**Ingress** solves this: a single NLB feeds a single **Ingress Controller** (running NGINX in this cluster), which acts as a reverse proxy and routes traffic to the right Service based on the URL.

```
Internet
   │
   ▼
[NLB] ← single load balancer for the whole cluster
   │
   ▼
[NGINX Ingress Controller pod]
   │  reads your Ingress resources
   ├─── host: YOURNAME.eks.ironlabs.online, path: /blue  ──▶ Service: app-blue
   ├─── host: YOURNAME.eks.ironlabs.online, path: /green ──▶ Service: app-green
   ├─── host: blue.YOURNAME.eks.ironlabs.online           ──▶ Service: app-blue
   └─── host: green.YOURNAME.eks.ironlabs.online          ──▶ Service: app-green
```

### Key terms

| Term | What it is |
|------|-----------|
| **Ingress** | A Kubernetes resource (YAML) that describes routing rules |
| **IngressClass** | Tells Kubernetes *which* controller handles this Ingress (we use `nginx`) |
| **Ingress Controller** | The NGINX pod that reads Ingress rules and proxies traffic |
| **external-dns** | A controller that watches Ingress resources and auto-creates DNS records in Route53 |

### What students don't need to install

The instructor has pre-installed everything on the cluster:
- **NGINX Ingress Controller** — the reverse proxy that handles your Ingress rules
- **external-dns** — creates DNS records in Route53 automatically when you create an Ingress
- **cert-manager** — manages TLS certificates (used in Lab 2)
- **Gateway API + NGINX Gateway Fabric** — used in Labs 3 and 4

You only need `kubectl` configured against this cluster.

---

## Step-by-step

### Step 1 — Set your student name

Pick a short lowercase name (no spaces, no dots). This becomes your subdomain.

```bash
# Replace "yourname" with your actual name (e.g. alice, bob, carmen)
export STUDENT_NAME=yourname
```

> **Important**: run this export in every terminal tab you open for this lab.

---

### Step 2 — Create your namespace

Each student works in their own namespace to avoid collisions.

```bash
kubectl create namespace $STUDENT_NAME
```

---

### Step 3 — Deploy the two sample apps

Copy the YAML below into a file called `apps.yaml`, then apply it.

```yaml
# ─── ConfigMap for the Blue app ───────────────────────────────────────────────
# Provides a simple HTML file that nginx will serve.
# The colored background makes it immediately obvious which app responded.
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-blue-html
  namespace: YOUR_STUDENT_NAME   # ← replace with your $STUDENT_NAME
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>App Blue</title></head>
    <body style="background:#1a73e8;color:#fff;font-family:sans-serif;
                 display:flex;align-items:center;justify-content:center;
                 height:100vh;margin:0">
      <div style="text-align:center">
        <h1>🔵 App Blue</h1>
        <p>Lab 1 — Ingress Path & Subdomain Routing</p>
      </div>
    </body>
    </html>
---
# ─── Deployment for the Blue app ─────────────────────────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
  namespace: YOUR_STUDENT_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-blue
  template:
    metadata:
      labels:
        app: app-blue
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html   # nginx serves files from here
      volumes:
        - name: html
          configMap:
            name: app-blue-html   # mounts the ConfigMap as files
---
# ─── ClusterIP Service for the Blue app ──────────────────────────────────────
# ClusterIP = internal only. The Ingress Controller will forward traffic to it.
# No LoadBalancer needed here — that's the whole point of Ingress!
apiVersion: v1
kind: Service
metadata:
  name: app-blue
  namespace: YOUR_STUDENT_NAME
spec:
  selector:
    app: app-blue   # matches pods with this label
  ports:
    - port: 80
      targetPort: 80
---
# ─── Same pattern for the Green app ──────────────────────────────────────────
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-green-html
  namespace: YOUR_STUDENT_NAME
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>App Green</title></head>
    <body style="background:#0f9d58;color:#fff;font-family:sans-serif;
                 display:flex;align-items:center;justify-content:center;
                 height:100vh;margin:0">
      <div style="text-align:center">
        <h1>🟢 App Green</h1>
        <p>Lab 1 — Ingress Path & Subdomain Routing</p>
      </div>
    </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
  namespace: YOUR_STUDENT_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-green
  template:
    metadata:
      labels:
        app: app-green
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
      volumes:
        - name: html
          configMap:
            name: app-green-html
---
apiVersion: v1
kind: Service
metadata:
  name: app-green
  namespace: YOUR_STUDENT_NAME
spec:
  selector:
    app: app-green
  ports:
    - port: 80
      targetPort: 80
```

Apply using `envsubst` to substitute your name automatically:

```bash
# envsubst replaces $STUDENT_NAME in the YAML with your actual name
envsubst < apps.yaml | kubectl apply -f -
```

Verify the pods are running:

```bash
kubectl get pods -n $STUDENT_NAME
# Expected: two pods in Running state (app-blue and app-green)
```

---

### Step 4 — Create the Ingress resources

Copy the YAML below into a file called `ingress.yaml`, then apply it.

```yaml
# ─── Ingress 1: PATH-BASED routing ────────────────────────────────────────────
# One hostname, different paths route to different backends.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-routing
  namespace: YOUR_STUDENT_NAME
  annotations:
    # This tells the NGINX controller to strip the path prefix before
    # forwarding to the backend. Without this, /blue would be forwarded
    # as /blue to the app, but the app only serves /.
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  # Which controller handles this Ingress. "nginx" is pre-installed on this cluster.
  ingressClassName: nginx
  rules:
    - host: YOUR_STUDENT_NAME.eks.ironlabs.online
      http:
        paths:
          - path: /blue
            pathType: Prefix   # matches /blue, /blue/, /blue/anything
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
# ─── Ingress 2: HOST-BASED (subdomain) routing ────────────────────────────────
# Different hostnames (subdomains) route to different backends.
# Note: no rewrite annotation needed here — the app receives / directly.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: subdomain-routing
  namespace: YOUR_STUDENT_NAME
spec:
  ingressClassName: nginx
  rules:
    # Traffic to blue.YOURNAME.eks.ironlabs.online goes to app-blue
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
    # Traffic to green.YOURNAME.eks.ironlabs.online goes to app-green
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

Apply:

```bash
envsubst < ingress.yaml | kubectl apply -f -
```

Check the Ingress objects:

```bash
kubectl get ingress -n $STUDENT_NAME
# Watch the ADDRESS column — it will fill in with the NLB hostname.
# external-dns picks this up and creates DNS records automatically.
```

---

### Step 5 — Wait for DNS propagation

external-dns watches your Ingress and creates DNS records in Route53. This takes about 60–90 seconds.

```bash
# Poll until your DNS record resolves
watch -n5 "nslookup ${STUDENT_NAME}.eks.ironlabs.online"
```

When you see an IP address (or the NLB hostname) in the answer, DNS is ready.

---

### Step 6 — Test path-based routing

```bash
# The /blue path should return the blue app HTML
curl http://${STUDENT_NAME}.eks.ironlabs.online/blue

# The /green path should return the green app HTML
curl http://${STUDENT_NAME}.eks.ironlabs.online/green
```

Or open in a browser — you'll see a blue or green colored page.

---

### Step 7 — Test subdomain routing

```bash
# The blue subdomain
curl http://blue.${STUDENT_NAME}.eks.ironlabs.online

# The green subdomain
curl http://green.${STUDENT_NAME}.eks.ironlabs.online
```

---

## What happened under the hood?

1. You created two **Ingress** resources with `ingressClassName: nginx`
2. The **NGINX Ingress Controller** pod detected them and updated its `nginx.conf` to add new `server {}` and `location {}` blocks
3. **external-dns** detected the hostnames in the Ingress `spec.rules[].host` field and called the Route53 API to create CNAME records pointing to the NLB
4. Traffic flow: `browser → DNS (Route53 CNAME) → NLB → NGINX pod → app-blue or app-green pod`

### Bonus: Inspect the generated NGINX config

```bash
NGINX_POD=$(kubectl get pod -n ingress-nginx \
  -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].metadata.name}')

# Show the server blocks nginx generated from your Ingress
kubectl exec -n ingress-nginx $NGINX_POD -- \
  nginx -T 2>/dev/null | grep -A 30 "server_name.*${STUDENT_NAME}"
```

---

## Clean up

```bash
envsubst < ingress.yaml | kubectl delete -f -
envsubst < apps.yaml | kubectl delete -f -
kubectl delete namespace $STUDENT_NAME
```

---

## Key takeaways

- **Ingress** is a routing layer, not an application — it proxies, not hosts
- **IngressClass** decouples routing rules from the controller implementation
- **Path routing** needs `rewrite-target` to strip the prefix before forwarding
- **Host routing** lets you run multiple virtual hosts through one load balancer
- **external-dns** makes DNS automatic — no manual Route53 clicks needed
