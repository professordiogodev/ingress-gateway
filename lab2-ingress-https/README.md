# Lab 2 — Ingress: HTTPS with Automatic TLS Certificates

## What is this lab about?

You'll expose a web application over **HTTPS** using a valid, browser-trusted TLS certificate — issued for free by **Let's Encrypt** and managed automatically by **cert-manager**.

You'll learn:
- How TLS termination works at the Ingress layer
- How cert-manager requests and renews certificates automatically
- How Let's Encrypt proves you own a domain using the DNS-01 challenge
- How to force HTTP → HTTPS redirects

Your app will be reachable at:
- `https://YOURNAME.eks.ironlabs.online` (HTTPS, with real cert)
- `http://YOURNAME.eks.ironlabs.online` → redirects to HTTPS automatically

---

## Concepts you need to know

### TLS termination at the Ingress

When a browser connects to `https://yoursite.com`, it negotiates a TLS handshake and expects a valid certificate. In this setup:

```
Browser (TLS handshake) ──▶ [NLB] ──▶ [NGINX Ingress Controller]
                                            │ holds the TLS cert & key
                                            │ decrypts HTTPS traffic
                                            ▼
                                       [webapp pod] ← receives plain HTTP
```

The **NGINX Ingress Controller** handles the TLS handshake. Your app pod never deals with TLS — it receives plain HTTP from NGINX. This is called **TLS termination**.

### cert-manager: automated certificate lifecycle

Managing TLS certs manually is painful:
- Request a cert from a CA → pay money or jump through hoops
- Store the private key somewhere safe
- Remember to renew every 90 days before it expires
- Update the Secret in Kubernetes

**cert-manager** automates all of this. It's a Kubernetes controller that:
1. Watches Ingress resources with the `cert-manager.io/cluster-issuer` annotation
2. Requests a certificate from Let's Encrypt
3. Solves the ACME challenge to prove domain ownership
4. Stores the cert + key in a Kubernetes Secret
5. Automatically renews the cert before it expires (at ~60 days)

### Let's Encrypt and the DNS-01 challenge

Let's Encrypt is a free, automated Certificate Authority. Before issuing a cert, it must verify you control the domain. This cluster uses the **DNS-01 challenge**:

```
cert-manager ──▶ Creates TXT record in Route53:
                 _acme-challenge.YOURNAME.eks.ironlabs.online = "some-token"

Let's Encrypt ──▶ Checks that TXT record exists via DNS
               ──▶ Domain ownership verified ✓
               ──▶ Issues certificate

cert-manager ──▶ Stores cert in Secret, deletes TXT record
```

DNS-01 is more powerful than HTTP-01 because it works even before your app is publicly reachable (e.g. during staging).

### ClusterIssuer: the instructor's gift to students

A **ClusterIssuer** is a cluster-wide cert-manager resource that defines *how* to get certificates (which ACME server, which challenge method, which AWS role to use for Route53 access).

The instructor has pre-created two:
- `letsencrypt-staging` — for testing (no rate limits, but cert is not browser-trusted)
- `letsencrypt-prod` — real browser-trusted certs (rate limited: 5 certs/domain/week)

You reference them by name in your Ingress annotation. You don't create them yourself.

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

Copy and apply the following YAML (replace `YOUR_STUDENT_NAME`):

```yaml
# ─── HTML content for the webapp ──────────────────────────────────────────────
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-html
  namespace: YOUR_STUDENT_NAME
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Secure WebApp</title></head>
    <body style="background:#6200ea;color:#fff;font-family:sans-serif;
                 display:flex;align-items:center;justify-content:center;
                 height:100vh;margin:0">
      <div style="text-align:center">
        <h1>🔒 Secure WebApp</h1>
        <p>Lab 2 — Ingress HTTPS</p>
        <p>You are connected over TLS!</p>
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
# ─── ClusterIP Service — internal only, NGINX will forward traffic here ───────
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
kubectl get pods -n $STUDENT_NAME
```

---

### Step 4 — Create the TLS Ingress

This is the key difference from Lab 1. Two changes:
1. A `cert-manager.io/cluster-issuer` annotation that triggers automatic cert issuance
2. A `tls:` block that tells NGINX which Secret contains the cert and which hostname to secure

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-tls
  namespace: YOUR_STUDENT_NAME
  annotations:
    # ── cert-manager integration ────────────────────────────────────────────
    # This annotation is the trigger. cert-manager watches for it and
    # automatically requests a certificate from the named ClusterIssuer.
    # The instructor pre-created "letsencrypt-prod" — you just reference it.
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # ── Force HTTPS ─────────────────────────────────────────────────────────
    # NGINX will return HTTP 308 (Permanent Redirect) for any HTTP request,
    # sending the browser to the HTTPS version automatically.
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - YOUR_STUDENT_NAME.eks.ironlabs.online
      # cert-manager creates and manages this Secret automatically.
      # The name here must match what cert-manager will store the cert under.
      secretName: YOUR_STUDENT_NAME-tls-secret
  rules:
    - host: YOUR_STUDENT_NAME.eks.ironlabs.online
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: webapp
                port:
                  number: 80
```

```bash
envsubst < ingress-tls.yaml | kubectl apply -f -
```

---

### Step 5 — Watch the certificate being issued

Once you apply the Ingress, cert-manager immediately starts working:

```bash
# Watch the Certificate and CertificateRequest objects appear
watch -n5 "kubectl get certificate,certificaterequest -n $STUDENT_NAME"
```

**Certificate lifecycle:**
1. `READY=False, Reason=Issuing` — cert-manager is requesting from Let's Encrypt
2. A `CertificateRequest` object appears — this is the actual CSR being processed
3. An `Order` object appears — the ACME order with Let's Encrypt
4. A `Challenge` object appears — DNS-01 challenge being solved via Route53
5. `READY=True` — certificate issued and stored in the Secret

```bash
# You can also watch the challenge objects
kubectl get challenge -n $STUDENT_NAME

# And see the full details
kubectl describe certificate -n $STUDENT_NAME
```

This takes **30–120 seconds**.

---

### Step 6 — Verify the Secret was created

```bash
kubectl get secret ${STUDENT_NAME}-tls-secret -n $STUDENT_NAME
# Should show a Secret of type kubernetes.io/tls
```

---

### Step 7 — Test HTTPS

```bash
# Full HTTPS request — should return your purple webapp
curl https://${STUDENT_NAME}.eks.ironlabs.online
```

Open in a browser. You should see the padlock icon. Click it to inspect the certificate — it should show **Issuer: Let's Encrypt**.

---

### Step 8 — Verify HTTP redirects to HTTPS

```bash
# -I = headers only, -L = follow redirects
curl -IL http://${STUDENT_NAME}.eks.ironlabs.online

# Expected output includes:
# HTTP/1.1 308 Permanent Redirect
# Location: https://YOURNAME.eks.ironlabs.online/
# ...then the HTTPS response
```

---

## Inspect the certificate details

```bash
# View the full certificate info from the Secret
kubectl get secret ${STUDENT_NAME}-tls-secret -n $STUDENT_NAME \
  -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 -noout -text \
  | grep -E "Issuer|Subject|Not Before|Not After"
```

---

## Clean up

```bash
envsubst < ingress-tls.yaml | kubectl delete -f -
envsubst < apps.yaml | kubectl delete -f -
kubectl delete namespace $STUDENT_NAME
```

---

## Key takeaways

- **TLS termination at the Ingress** means your backend pods serve plain HTTP — simpler and faster
- **cert-manager** + **ClusterIssuer** makes certificate management zero-touch
- **DNS-01 challenge** proves domain ownership via Route53, enabling automation without HTTP access to the domain
- The Ingress `secretName` is the contract between cert-manager (writes the Secret) and NGINX (reads the Secret)
- **308 Permanent Redirect** for HTTP → HTTPS is best practice; browsers cache it and skip HTTP entirely on future visits
