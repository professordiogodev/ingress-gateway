# Lab 3 — Gateway API: Path & Subdomain Routing

## What is this lab about?

You'll do the same routing as Lab 1 (path and subdomain) but using **Gateway API** instead of Ingress. Gateway API is the next-generation Kubernetes standard for HTTP routing, and it's already stable (v1) in Kubernetes 1.28+.

Your apps will be reachable at:
- `http://YOURNAME.eks.ironlabs.online/blue` → Blue app
- `http://YOURNAME.eks.ironlabs.online/green` → Green app
- `http://blue.YOURNAME.eks.ironlabs.online` → Blue app
- `http://green.YOURNAME.eks.ironlabs.online` → Green app

---

## Concepts you need to know

### Why Gateway API? What's wrong with Ingress?

Ingress has been around since Kubernetes 1.1 and works well for simple cases. But it has real limitations:

1. **Non-standard features need annotations** — NGINX's `nginx.ingress.kubernetes.io/rewrite-target` is completely different from Traefik's or AWS ALB's annotations. Your YAML is not portable between controllers.

2. **No role separation** — a developer creating routing rules and a cluster admin controlling which load balancers exist both use the same `Ingress` resource. There's no way to give developers routing control without also giving them the ability to change cluster-level settings.

3. **Expressiveness limits** — traffic splitting (50%/50% canary deployments), header-based routing, gRPC routing all require annotations or are impossible.

**Gateway API** was designed by SIG Network to fix all of this. It's been stable since Kubernetes 1.28 and is actively replacing Ingress.

### The role-oriented model

Gateway API splits routing into three separate Kubernetes resources, each owned by a different team:

```
┌─────────────────────────────────────────────────────────┐
│ GatewayClass  (created by: Platform/Infrastructure team) │
│ "Use NGINX Gateway Fabric as the controller"             │
└─────────────────────────┬───────────────────────────────┘
                          │ references
┌─────────────────────────▼───────────────────────────────┐
│ Gateway  (created by: Cluster Admin)                     │
│ "Listen on port 80, accept routes for *.ironlabs.online" │
└────────────┬──────────────────────────┬─────────────────┘
             │ parentRef                 │ parentRef
┌────────────▼────────┐    ┌────────────▼────────────────┐
│ HTTPRoute           │    │ HTTPRoute                   │
│ (Developer: Alice)  │    │ (Developer: Bob)            │
│ /blue → app-blue    │    │ /green → app-green          │
└─────────────────────┘    └─────────────────────────────┘
```

This means:
- Platform team controls *what infrastructure exists* (GatewayClass)
- Cluster admin controls *what entry points exist* (Gateway)
- Developers control *their own routes* (HTTPRoute) — without touching shared infra

### The four key resources

| Resource | Who creates it | What it defines |
|----------|---------------|-----------------|
| **GatewayClass** | Instructor (once) | Which implementation to use (`nginx` = NGINX Gateway Fabric) |
| **Gateway** | You (per lab) | Entry point: port 80, which namespaces can attach routes |
| **HTTPRoute** | You (per app) | Routing rules: hostnames + paths → backend Services |
| **ReferenceGrant** | Namespace owner | Cross-namespace access (needed for TLS Secrets in Lab 4) |

### How external-dns works with Gateway API

In Lab 1, external-dns read the hostnames from the Ingress `spec.rules[].host` field. In this lab, external-dns reads hostnames from the `external-dns.alpha.kubernetes.io/hostname` annotation on the Gateway. When the Gateway gets an address (NLB hostname), external-dns creates a CNAME pointing to it.

---

## Step-by-step

### Step 1 — Set your name

```bash
export STUDENT_NAME=yourname
```

### Step 2 — Create your namespace

```bash
kubectl create namespace $STUDENT_NAME
```

### Step 3 — Deploy the two apps

Same apps as Lab 1. Save as `apps.yaml` (replace `YOUR_STUDENT_NAME`):

```yaml
# ─── Blue app ─────────────────────────────────────────────────────────────────
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-blue-html
  namespace: YOUR_STUDENT_NAME
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
        <p>Lab 3 — Gateway API Routing</p>
      </div>
    </body>
    </html>
---
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
              mountPath: /usr/share/nginx/html
      volumes:
        - name: html
          configMap:
            name: app-blue-html
---
apiVersion: v1
kind: Service
metadata:
  name: app-blue
  namespace: YOUR_STUDENT_NAME
spec:
  selector:
    app: app-blue
  ports:
    - port: 80
      targetPort: 80
---
# ─── Green app ────────────────────────────────────────────────────────────────
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
        <p>Lab 3 — Gateway API Routing</p>
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

```bash
envsubst < apps.yaml | kubectl apply -f -
kubectl get pods -n $STUDENT_NAME
```

---

### Step 4 — Create the Gateway

The Gateway is your entry point. Think of it like claiming a slice of the shared load balancer — you declare which hostnames you want to receive traffic for.

Save as `gateway.yaml` (replace `YOUR_STUDENT_NAME`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: YOUR_STUDENT_NAME-gateway
  namespace: YOUR_STUDENT_NAME
  annotations:
    # external-dns reads this annotation to know which DNS records to create.
    # It will create a CNAME for each hostname pointing to the Gateway's NLB address.
    external-dns.alpha.kubernetes.io/hostname: >-
      YOUR_STUDENT_NAME.eks.ironlabs.online,
      blue.YOUR_STUDENT_NAME.eks.ironlabs.online,
      green.YOUR_STUDENT_NAME.eks.ironlabs.online
spec:
  # "nginx" is the GatewayClass created by the instructor using NGINX Gateway Fabric.
  # This tells Kubernetes which controller manages this Gateway.
  gatewayClassName: nginx

  listeners:
    - name: http
      port: 80
      protocol: HTTP
      # allowedRoutes controls which HTTPRoute resources can attach to this listener.
      # "Same" = only HTTPRoutes in the same namespace (YOUR_STUDENT_NAME).
      # You could also use "All" or label selectors for cross-namespace routes.
      allowedRoutes:
        namespaces:
          from: Same
```

```bash
envsubst < gateway.yaml | kubectl apply -f -
```

Watch the Gateway get an address (the controller provisions infrastructure):

```bash
watch -n5 "kubectl get gateway -n $STUDENT_NAME"
# Wait until PROGRAMMED=True and ADDRESS is populated
```

---

### Step 5 — Create the HTTPRoutes

HTTPRoutes define the actual routing rules. They attach to the Gateway via `parentRefs`. Notice these are standard Kubernetes resources — no controller-specific annotations needed.

Save as `httproutes.yaml` (replace `YOUR_STUDENT_NAME`):

```yaml
# ─── HTTPRoute 1: PATH-BASED routing ──────────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: path-routing
  namespace: YOUR_STUDENT_NAME
spec:
  # Attach this route to the Gateway defined above.
  # The route only becomes active when the Gateway accepts it.
  parentRefs:
    - name: YOUR_STUDENT_NAME-gateway
      namespace: YOUR_STUDENT_NAME

  # This route only handles traffic for this specific hostname.
  hostnames:
    - "YOUR_STUDENT_NAME.eks.ironlabs.online"

  rules:
    # Rule 1: /blue → app-blue
    - matches:
        - path:
            type: PathPrefix
            value: /blue
      filters:
        # URLRewrite strips /blue from the path before forwarding.
        # Without this, the app receives /blue but only serves /.
        # This is equivalent to nginx's rewrite-target annotation — but standardized.
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplaceFullPath
              replaceFullPath: /
      backendRefs:
        - name: app-blue
          port: 80

    # Rule 2: /green → app-green
    - matches:
        - path:
            type: PathPrefix
            value: /green
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplaceFullPath
              replaceFullPath: /
      backendRefs:
        - name: app-green
          port: 80
---
# ─── HTTPRoute 2: HOST-BASED routing for blue subdomain ───────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: subdomain-blue
  namespace: YOUR_STUDENT_NAME
spec:
  parentRefs:
    - name: YOUR_STUDENT_NAME-gateway
      namespace: YOUR_STUDENT_NAME
  # Traffic matching this hostname is handled by this route.
  # The Gateway must have a listener that accepts this hostname.
  hostnames:
    - "blue.YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - backendRefs:
        - name: app-blue
          port: 80
---
# ─── HTTPRoute 3: HOST-BASED routing for green subdomain ──────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: subdomain-green
  namespace: YOUR_STUDENT_NAME
spec:
  parentRefs:
    - name: YOUR_STUDENT_NAME-gateway
      namespace: YOUR_STUDENT_NAME
  hostnames:
    - "green.YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - backendRefs:
        - name: app-green
          port: 80
```

```bash
envsubst < httproutes.yaml | kubectl apply -f -
```

Check the routes are accepted:

```bash
kubectl get httproute -n $STUDENT_NAME

# For more detail, check the status conditions
kubectl describe httproute path-routing -n $STUDENT_NAME
# Look for: "Accepted: True" and "ResolvedRefs: True"
```

---

### Step 6 — Wait for DNS (~60 seconds)

```bash
watch -n5 "nslookup ${STUDENT_NAME}.eks.ironlabs.online"
```

### Step 7 — Test path routing

```bash
curl http://${STUDENT_NAME}.eks.ironlabs.online/blue
curl http://${STUDENT_NAME}.eks.ironlabs.online/green
```

### Step 8 — Test subdomain routing

```bash
curl http://blue.${STUDENT_NAME}.eks.ironlabs.online
curl http://green.${STUDENT_NAME}.eks.ironlabs.online
```

---

## Compare: Ingress (Lab 1) vs Gateway API (Lab 3)

| Feature | Ingress | Gateway API |
|---------|---------|-------------|
| Path rewrite | `nginx.ingress.kubernetes.io/rewrite-target: /` (non-standard) | `URLRewrite` filter (standard, works on any GW implementation) |
| Host routing | Ingress `spec.rules[].host` | HTTPRoute `hostnames` field |
| Role separation | None — one resource for everything | GatewayClass / Gateway / HTTPRoute |
| Traffic splitting | Not supported natively | Supported: `backendRefs` with `weight` |
| gRPC | Not supported | Supported via `GRPCRoute` |
| TCP/UDP | Not supported | Supported via `TCPRoute`/`UDPRoute` |
| Portability | Annotations are controller-specific | All features standardized in the API spec |

---

## Inspect route status

```bash
# See which parent the route is attached to and whether it's healthy
kubectl get httproute path-routing -n $STUDENT_NAME -o yaml | grep -A 20 "status:"
```

---

## Clean up

```bash
envsubst < httproutes.yaml | kubectl delete -f -
envsubst < gateway.yaml | kubectl delete -f -
envsubst < apps.yaml | kubectl delete -f -
kubectl delete namespace $STUDENT_NAME
```

---

## Key takeaways

- **Gateway API is the future** — Ingress is in maintenance mode; new features go to Gateway API
- **GatewayClass / Gateway / HTTPRoute** maps to Platform / Admin / Developer responsibilities
- **Routing rules in HTTPRoute are standardized** — no more controller-specific annotations
- **`parentRefs`** is how routes attach to Gateways — the Gateway must accept the route's namespace
- **`URLRewrite` filter** replaces path rewrites that used to require NGINX annotations
