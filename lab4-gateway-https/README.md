# Lab 4 — Gateway API: HTTPS with TLS Certificates

## What is this lab about?

You'll configure **HTTPS** using Gateway API — combining the TLS automation from Lab 2 with the Gateway API routing model from Lab 3.

You'll learn:
- How TLS configuration lives on the **Gateway listener** (not on the route)
- How to use cert-manager's `Certificate` resource explicitly (vs the auto-annotation approach in Lab 2)
- How to implement HTTP → HTTPS redirect using a declarative `RequestRedirect` filter
- The `sectionName` field: attaching HTTPRoutes to specific listeners

Your app will be reachable at:
- `https://YOURNAME.eks.ironlabs.online` (HTTPS, real cert)
- `http://YOURNAME.eks.ironlabs.online` → 301 redirect to HTTPS

---

## Concepts you need to know

### TLS in Gateway API: it lives on the listener, not the route

In Lab 2 (Ingress), you put TLS configuration inside the Ingress resource itself:

```yaml
# Lab 2: TLS config in Ingress
spec:
  tls:
    - hosts: [...]
      secretName: my-tls-secret
```

In Gateway API, TLS lives on the **Gateway listener**. This is the key design difference:

```
Gateway (port 443, HTTPS listener)
  └── tls:
        mode: Terminate
        certificateRefs:
          - name: my-tls-secret   ← Gateway holds the cert config

HTTPRoute (attached to the https listener)
  └── rules:
        - backendRefs: [webapp]   ← Route has no TLS knowledge
```

Why is this better? Because **platform teams control TLS** (what certs are allowed, which protocols, cipher suites) while **developers just attach routes** to TLS-enabled listeners. A developer can't bypass TLS by modifying their HTTPRoute.

### Two Gateway listeners: HTTP and HTTPS

In this lab your Gateway has two listeners:

```
Gateway
  ├── Listener: http  (port 80)   ← handles HTTP traffic
  │     └── HTTPRoute: http-redirect  → sends 301 to https://...
  │
  └── Listener: https (port 443)  ← handles HTTPS traffic (terminates TLS)
        └── HTTPRoute: webapp-https → forwards to webapp pod
```

Traffic flow:

```
Browser (HTTP)  ──▶ [NLB] ──▶ Gateway (port 80) ──▶ HTTPRoute: 301 redirect
Browser (HTTPS) ──▶ [NLB] ──▶ Gateway (port 443, TLS) ──▶ HTTPRoute ──▶ webapp pod
```

### cert-manager: explicit Certificate resource

In Lab 2, you just added an annotation to the Ingress and cert-manager auto-detected it (called "ingress-shim"). In Gateway API you have two approaches:

**Approach A (this lab):** Create a `Certificate` resource explicitly. cert-manager issues the cert and stores it in a Secret. The Gateway's listener references that Secret.

```
You create:  Certificate resource  ──▶  cert-manager issues cert  ──▶  Secret
                                                                          ▲
                                    Gateway listener references ──────────┘
```

This is more explicit and easier to understand — you can see exactly when the cert is ready before creating the Gateway.

**Approach B:** cert-manager Gateway API integration (cert-manager ≥ 1.15 + feature gate). cert-manager watches Gateway listeners and manages certs automatically. More automated but requires extra configuration.

### `sectionName`: routing to specific listeners

When your Gateway has multiple listeners, HTTPRoutes use `sectionName` to attach to a specific one:

```yaml
parentRefs:
  - name: my-gateway
    sectionName: http    # attach only to the "http" listener
```

Without `sectionName`, the route attaches to all listeners — which would send traffic through both HTTP and HTTPS listeners, and could break your redirect logic.

### HTTP → HTTPS redirect: the declarative way

In Lab 2 you used an annotation: `nginx.ingress.kubernetes.io/ssl-redirect: "true"`. In Gateway API, redirects are a first-class feature — a filter in the HTTPRoute:

```yaml
rules:
  - filters:
      - type: RequestRedirect
        requestRedirect:
          scheme: https
          statusCode: 301
```

This is implementation-agnostic — it works the same on NGINX, Envoy, or any other Gateway API controller.

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

### Step 3 — Deploy the webapp

Save as `apps.yaml` (replace `YOUR_STUDENT_NAME`):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-html
  namespace: YOUR_STUDENT_NAME
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Secure Gateway App</title></head>
    <body style="background:#bf360c;color:#fff;font-family:sans-serif;
                 display:flex;align-items:center;justify-content:center;
                 height:100vh;margin:0">
      <div style="text-align:center">
        <h1>🔐 Secure Gateway App</h1>
        <p>Lab 4 — Gateway API HTTPS</p>
        <p>TLS terminated at the Gateway!</p>
      </div>
    </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: YOUR_STUDENT_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
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
            name: webapp-html
---
apiVersion: v1
kind: Service
metadata:
  name: webapp
  namespace: YOUR_STUDENT_NAME
spec:
  selector:
    app: webapp
  ports:
    - port: 80
      targetPort: 80
```

```bash
envsubst < apps.yaml | kubectl apply -f -
```

---

### Step 4 — Request a TLS certificate explicitly

This creates a cert-manager `Certificate` resource that will:
1. Talk to Let's Encrypt
2. Solve the DNS-01 challenge via Route53
3. Store the resulting cert in a Kubernetes Secret

Save as `certificate.yaml` (replace `YOUR_STUDENT_NAME`):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: YOUR_STUDENT_NAME-tls
  namespace: YOUR_STUDENT_NAME
spec:
  # The Secret name where cert-manager will store the certificate + private key.
  # The Gateway (next step) references this exact Secret name.
  secretName: YOUR_STUDENT_NAME-tls-secret

  issuerRef:
    # Reference the cluster-wide issuer the instructor pre-created.
    name: letsencrypt-prod
    kind: ClusterIssuer

  # The domain names this certificate is valid for.
  dnsNames:
    - YOUR_STUDENT_NAME.eks.ironlabs.online
```

```bash
envsubst < certificate.yaml | kubectl apply -f -
```

Watch cert-manager work:

```bash
# Poll until READY=True (30–120 seconds)
watch -n5 "kubectl get certificate -n $STUDENT_NAME"

# Detailed view of what's happening
kubectl describe certificate ${STUDENT_NAME}-tls -n $STUDENT_NAME

# You can also watch the underlying ACME objects
kubectl get order,challenge -n $STUDENT_NAME
```

**Do not proceed until `READY=True`.** The Gateway needs the Secret to exist before it can serve HTTPS.

---

### Step 5 — Create the Gateway with two listeners

Save as `gateway-tls.yaml` (replace `YOUR_STUDENT_NAME`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: YOUR_STUDENT_NAME-gateway
  namespace: YOUR_STUDENT_NAME
  annotations:
    # external-dns creates a DNS record for this hostname pointing to the Gateway NLB.
    external-dns.alpha.kubernetes.io/hostname: YOUR_STUDENT_NAME.eks.ironlabs.online
spec:
  gatewayClassName: nginx

  listeners:
    # ── Listener 1: HTTP (port 80) ──────────────────────────────────────────
    # Accepts HTTP traffic. We'll attach an HTTPRoute that redirects to HTTPS.
    - name: http
      port: 80
      protocol: HTTP
      hostname: "YOUR_STUDENT_NAME.eks.ironlabs.online"
      allowedRoutes:
        namespaces:
          from: Same

    # ── Listener 2: HTTPS (port 443) ────────────────────────────────────────
    # Accepts HTTPS traffic and terminates TLS using the cert-manager Secret.
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "YOUR_STUDENT_NAME.eks.ironlabs.online"
      tls:
        # Terminate = the Gateway decrypts TLS and forwards plain HTTP to backends.
        # Passthrough = the Gateway forwards encrypted traffic to backends (they do TLS).
        mode: Terminate
        certificateRefs:
          # This Secret was created by cert-manager in Step 4.
          # The Gateway reads the cert and key from here for TLS termination.
          - name: YOUR_STUDENT_NAME-tls-secret
      allowedRoutes:
        namespaces:
          from: Same
```

```bash
envsubst < gateway-tls.yaml | kubectl apply -f -

# Wait for the Gateway to be programmed
watch -n5 "kubectl get gateway -n $STUDENT_NAME"
# PROGRAMMED=True means the controller configured the load balancer
```

---

### Step 6 — Create the HTTPRoutes

Two routes: one for HTTP→HTTPS redirect, one for the actual app traffic.

Save as `httproutes.yaml` (replace `YOUR_STUDENT_NAME`):

```yaml
# ─── HTTPRoute 1: HTTP → HTTPS redirect ───────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-redirect
  namespace: YOUR_STUDENT_NAME
spec:
  parentRefs:
    - name: YOUR_STUDENT_NAME-gateway
      namespace: YOUR_STUDENT_NAME
      # sectionName targets a specific listener by name.
      # This route only attaches to the "http" listener (port 80).
      # Without sectionName, it would attach to both listeners, which would
      # cause the redirect to loop on the HTTPS listener.
      sectionName: http
  hostnames:
    - "YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - filters:
        # RequestRedirect is a standard Gateway API filter — no annotations needed.
        # 301 = Moved Permanently (browser caches this redirect)
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
---
# ─── HTTPRoute 2: HTTPS → webapp ──────────────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: webapp-https
  namespace: YOUR_STUDENT_NAME
spec:
  parentRefs:
    - name: YOUR_STUDENT_NAME-gateway
      namespace: YOUR_STUDENT_NAME
      # This route only attaches to the "https" listener (port 443).
      # The Gateway handles TLS; this route just does plain HTTP routing.
      sectionName: https
  hostnames:
    - "YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - backendRefs:
        - name: webapp
          port: 80
```

```bash
envsubst < httproutes.yaml | kubectl apply -f -
kubectl get httproute -n $STUDENT_NAME
```

---

### Step 7 — Wait for DNS

```bash
watch -n5 "nslookup ${STUDENT_NAME}.eks.ironlabs.online"
```

### Step 8 — Test HTTPS

```bash
curl https://${STUDENT_NAME}.eks.ironlabs.online
```

Open in a browser — padlock icon should show a valid Let's Encrypt cert.

### Step 9 — Verify HTTP → HTTPS redirect

```bash
# -I = show headers, don't download body
curl -I http://${STUDENT_NAME}.eks.ironlabs.online

# Expected:
# HTTP/1.1 301 Moved Permanently
# Location: https://YOURNAME.eks.ironlabs.online/
```

---

## Inspect the TLS handshake

```bash
# Full TLS certificate details
echo | openssl s_client -connect ${STUDENT_NAME}.eks.ironlabs.online:443 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
```

---

## Compare: Ingress HTTPS (Lab 2) vs Gateway API HTTPS (Lab 4)

| Concept | Ingress HTTPS (Lab 2) | Gateway API HTTPS (Lab 4) |
|---------|----------------------|--------------------------|
| Where TLS config lives | Inside the Ingress resource | On the Gateway listener |
| Who triggers cert issuance | Ingress annotation (`cert-manager.io/cluster-issuer`) | Explicit `Certificate` resource |
| HTTP→HTTPS redirect | `nginx.ingress.kubernetes.io/ssl-redirect` annotation | `RequestRedirect` filter in HTTPRoute |
| Listener targeting | N/A (one resource) | `sectionName` in HTTPRoute `parentRefs` |
| Who controls TLS | Anyone who can create an Ingress | Gateway admin (separate from route authors) |
| Portability | NGINX-specific annotation | Standard Gateway API filter |

---

## Clean up

```bash
envsubst < httproutes.yaml | kubectl delete -f -
envsubst < gateway-tls.yaml | kubectl delete -f -
envsubst < certificate.yaml | kubectl delete -f -
envsubst < apps.yaml | kubectl delete -f -
kubectl delete namespace $STUDENT_NAME
```

---

## Key takeaways

- **TLS lives on the Gateway listener**, not the HTTPRoute — enabling role-based TLS policy
- **Explicit `Certificate` resource** gives you full visibility into cert issuance status before the Gateway starts
- **`sectionName`** in `parentRefs` is how you target a specific listener — critical for the redirect/HTTPS split
- **`RequestRedirect` filter** is declarative and controller-agnostic — no annotations, works everywhere
- **`tls.mode: Terminate`** vs `Passthrough`: Terminate = Gateway decrypts, Passthrough = backend decrypts (mTLS, etc.)
