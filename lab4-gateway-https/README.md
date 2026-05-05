# Lab 4 — Gateway API: HTTPS with TLS Certificates

## Before this lab

```bash
# Verify cert-manager and ClusterIssuers are ready
kubectl get pods -n cert-manager
kubectl get clusterissuer

# Verify NGINX Gateway Fabric is running
kubectl get pods -n nginx-gateway

# Set your name if you haven't already
export STUDENT_NAME=yourname
```

---

## What is this lab about?

You'll configure **HTTPS** using Gateway API — combining cert-manager's TLS automation from Lab 2 with the Gateway API routing model from Lab 3.

```
https://YOURNAME.eks.ironlabs.online   ← HTTPS, valid cert, TLS terminated at the Gateway
http://YOURNAME.eks.ironlabs.online    ← 301 redirect to HTTPS
```

---

## Concepts

### Where TLS config lives: Gateway vs Ingress

In Lab 2, TLS configuration was inside the Ingress resource itself:

```yaml
# Lab 2: TLS is part of the Ingress
spec:
  tls:
    - hosts: [...]
      secretName: my-tls-secret
```

In Gateway API, **TLS configuration belongs on the Gateway listener**, not on the HTTPRoute:

```
Gateway
  ├── listener: http  (port 80)   ← handles unencrypted traffic
  └── listener: https (port 443)  ← terminates TLS, holds the cert reference
        │
        └── HTTPRoute             ← knows nothing about TLS, just routes
```

Why is this better? In a company with a shared cluster, the platform team controls which certificates are allowed at the Gateway level. Application developers attach HTTPRoutes without being able to change TLS policy. The security boundary is enforced by the resource model, not by access controls on a single resource.

### Two listeners, two HTTPRoutes

Your Gateway in this lab has two listeners:

```
Gateway (port 80, HTTP listener)
  └── HTTPRoute: http-redirect
        └── rule: redirect all traffic to https://...  (301)

Gateway (port 443, HTTPS listener, holds TLS cert)
  └── HTTPRoute: webapp-https
        └── rule: forward to webapp pod
```

This is why `sectionName` matters: when a Gateway has multiple listeners, an HTTPRoute uses `sectionName` in its `parentRefs` to attach to a specific one. Without it, the route attaches to all listeners — which would cause the redirect to loop.

### cert-manager with Gateway API: explicit Certificate

In Lab 2, you added an annotation to the Ingress and cert-manager automatically detected it and managed the cert (called "ingress-shim"). That convenience doesn't exist with Gateway API.

Here you create a `Certificate` resource explicitly:

```
You create Certificate → cert-manager issues cert → stores in Secret
                                                          ▲
                                 Gateway listener references ──┘
```

The explicit approach is actually clearer for learning: you can see exactly when the cert is ready (when `READY=True` on the Certificate object) before the Gateway even starts.

### HTTP → HTTPS redirect: the declarative way

In Lab 2 you set `nginx.ingress.kubernetes.io/ssl-redirect: "true"` as an annotation. In Gateway API, redirects are a **first-class filter** in the HTTPRoute — no annotations, standardized across all implementations:

```yaml
filters:
  - type: RequestRedirect
    requestRedirect:
      scheme: https
      statusCode: 301
```

---

## Step-by-step

### Step 1 — Set your name

```bash
export STUDENT_NAME=yourname
```

### Step 2 — Deploy the webapp

```bash
kubectl apply -f apps.yaml
```

Creates the `lab4` namespace and a single webapp. No `envsubst` needed.

```bash
kubectl get pods -n lab4
```

---

### Step 3 — Request a TLS certificate

Create the Certificate resource. cert-manager will immediately start the ACME flow.

```bash
envsubst < certificate.yaml | kubectl apply -f -
```

The Certificate YAML (in `certificate.yaml`):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: webapp-tls
  namespace: lab4
spec:
  # The name of the Secret cert-manager will create.
  # The Gateway's TLS listener references this exact name — get it right.
  secretName: webapp-tls-secret

  issuerRef:
    name: letsencrypt-prod     # ClusterIssuer created during setup
    kind: ClusterIssuer

  dnsNames:
    - YOUR_STUDENT_NAME.eks.ironlabs.online
```

Watch until it's ready (DNS-01 challenge via Route53, takes 30–120 seconds):

```bash
watch -n5 "kubectl get certificate -n lab4"
# Wait until READY=True before proceeding
```

You can also watch the full chain of ACME objects being created and resolved:

```bash
kubectl get certificate,certificaterequest,order,challenge -n lab4
```

**Don't proceed until `READY=True`.** The Gateway needs the Secret to exist before it can configure the HTTPS listener.

---

### Step 4 — Create the Gateway with two listeners

```bash
envsubst < gateway-tls.yaml | kubectl apply -f -
```

The Gateway YAML (in `gateway-tls.yaml`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: lab4
  annotations:
    # external-dns will create a CNAME for this hostname pointing to the Gateway's NLB.
    external-dns.alpha.kubernetes.io/hostname: YOUR_STUDENT_NAME.eks.ironlabs.online
spec:
  gatewayClassName: nginx
  listeners:
    # ── Listener 1: HTTP (port 80) ──────────────────────────────────────────────
    # Accepts plain HTTP. We'll attach an HTTPRoute that redirects to HTTPS.
    - name: http
      port: 80
      protocol: HTTP
      hostname: "YOUR_STUDENT_NAME.eks.ironlabs.online"
      allowedRoutes:
        namespaces:
          from: Same

    # ── Listener 2: HTTPS (port 443) ────────────────────────────────────────────
    # Accepts HTTPS traffic. Terminates TLS using the cert-manager Secret.
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "YOUR_STUDENT_NAME.eks.ironlabs.online"
      tls:
        # Terminate: Gateway decrypts TLS, forwards plain HTTP to backends.
        # Passthrough would forward encrypted traffic as-is to the backend pods.
        mode: Terminate
        certificateRefs:
          # This Secret was created by cert-manager in Step 3.
          # If the Secret doesn't exist yet, the Gateway starts but the
          # HTTPS listener won't work until cert-manager finishes.
          - name: webapp-tls-secret
      allowedRoutes:
        namespaces:
          from: Same
```

Wait for the Gateway to be programmed:

```bash
watch -n5 "kubectl get gateway -n lab4"
# PROGRAMMED=True means the NLB and NGINX are fully configured
```

---

### Step 5 — Create the HTTPRoutes

Two routes: one for redirect, one for the actual app.

```bash
envsubst < httproutes.yaml | kubectl apply -f -
```

The HTTPRoute YAML (in `httproutes.yaml`):

```yaml
# ─── Route 1: HTTP → HTTPS redirect ───────────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-redirect
  namespace: lab4
spec:
  parentRefs:
    - name: my-gateway
      namespace: lab4
      # sectionName targets a specific listener by name.
      # Attaching only to "http" (port 80) means this redirect rule
      # doesn't affect the HTTPS listener — no redirect loop.
      sectionName: http
  hostnames:
    - "YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - filters:
        # RequestRedirect is a standardized Gateway API filter.
        # Compare to Lab 2's "nginx.ingress.kubernetes.io/ssl-redirect: true" annotation.
        # Same behavior, but now it's part of the Kubernetes API spec.
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
---
# ─── Route 2: HTTPS → webapp ──────────────────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: webapp-https
  namespace: lab4
spec:
  parentRefs:
    - name: my-gateway
      namespace: lab4
      sectionName: https    # attach only to the HTTPS listener
  hostnames:
    - "YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - backendRefs:
        - name: webapp
          port: 80
```

```bash
kubectl get httproute -n lab4
```

---

### Step 6 — Wait for DNS

```bash
watch -n5 "nslookup ${STUDENT_NAME}.eks.ironlabs.online"
```

---

### Step 7 — Test HTTPS

```bash
curl https://${STUDENT_NAME}.eks.ironlabs.online
```

Open in a browser — the padlock icon should show a valid Let's Encrypt certificate.

---

### Step 8 — Verify HTTP → HTTPS redirect

```bash
curl -I http://${STUDENT_NAME}.eks.ironlabs.online

# Expected:
# HTTP/1.1 301 Moved Permanently
# Location: https://YOURNAME.eks.ironlabs.online/
```

---

## Inspect the TLS certificate

```bash
echo | openssl s_client \
  -connect ${STUDENT_NAME}.eks.ironlabs.online:443 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
```

---

## Compare: Lab 2 (Ingress HTTPS) vs Lab 4 (Gateway API HTTPS)

| Concept | Ingress + cert-manager | Gateway API + cert-manager |
|---------|----------------------|--------------------------|
| Where TLS config lives | Inside the Ingress `tls:` block | On the Gateway listener |
| cert-manager trigger | `cert-manager.io/cluster-issuer` annotation on Ingress | Explicit `Certificate` resource |
| HTTP→HTTPS redirect | `ssl-redirect: "true"` annotation (NGINX-specific) | `RequestRedirect` filter (standardized) |
| Listener targeting | Not applicable — one resource | `sectionName` in HTTPRoute `parentRefs` |
| Who controls TLS | Anyone who can edit the Ingress | Gateway admin (separate from route authors) |

---

## Clean up

```bash
envsubst < httproutes.yaml | kubectl delete -f -
envsubst < gateway-tls.yaml | kubectl delete -f -
envsubst < certificate.yaml | kubectl delete -f -
kubectl delete -f apps.yaml
```

---

## Key takeaways

- **TLS config belongs on the Gateway listener**, not the route — platform team controls TLS, developers attach routes
- **Create the Certificate first** — the Gateway needs the Secret to exist before the HTTPS listener works
- **`sectionName`** in `parentRefs` is how you target a specific listener — critical when the Gateway has both HTTP and HTTPS
- **`RequestRedirect` filter** is the declarative, portable replacement for NGINX's ssl-redirect annotation
- **`tls.mode: Terminate`** = Gateway decrypts; **`Passthrough`** = backend decrypts (used for end-to-end mTLS)

---

You've now completed all four labs. You've operated both sides of the ingress-to-Gateway-API migration that the industry is working through right now. See [`00-intro-2026.md`](../00-intro-2026.md) for context on where the ecosystem goes from here.
