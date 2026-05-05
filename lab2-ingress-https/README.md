# Lab 2 — Ingress: HTTPS with Automatic TLS Certificates

## Before this lab

```bash
# Verify cert-manager is running
kubectl get pods -n cert-manager

# Verify ClusterIssuers are ready
kubectl get clusterissuer

# Set your name if you haven't already
export STUDENT_NAME=yourname
```

If either `letsencrypt-staging` or `letsencrypt-prod` shows `READY=False`, wait a few seconds and check again — they need to register with the Let's Encrypt ACME server on first use.

---

## What is this lab about?

You'll serve a web application over **HTTPS** using a real, browser-trusted TLS certificate issued automatically by **Let's Encrypt** and managed by **cert-manager**.

```
https://YOURNAME.eks.ironlabs.online      ← HTTPS, valid cert
http://YOURNAME.eks.ironlabs.online       ← redirects to HTTPS automatically
```

---

## Concepts

### TLS termination at the Ingress

When a browser connects to `https://yoursite.com`, it negotiates a TLS handshake. In this setup, NGINX handles that handshake — it holds the certificate and private key, decrypts the traffic, and forwards plain HTTP to your pod. Your app never deals with TLS.

```
Browser (TLS)  →  NLB  →  NGINX Ingress Controller
                              │ decrypts TLS, holds cert
                              ▼
                         webapp pod  ← receives plain HTTP
```

This pattern is called **TLS termination**. It's the most common approach for web apps because your backend code stays simple and NGINX handles the cryptography.

### cert-manager: automated certificate lifecycle

Managing TLS certs manually is painful:
- Request a cert from a CA → pay money or complete ownership proofs manually
- Store the private key somewhere secure
- Renew before expiry every 90 days
- Update the Kubernetes Secret after renewal

**cert-manager** eliminates all of this. It watches your cluster for the `cert-manager.io/cluster-issuer` annotation on Ingress resources, then:
1. Requests a certificate from Let's Encrypt
2. Proves domain ownership (DNS-01 challenge via Route53)
3. Stores the cert + key in a Kubernetes Secret
4. Monitors expiry and renews automatically at ~60 days

### Let's Encrypt and the DNS-01 challenge

Let's Encrypt is a free, automated Certificate Authority. Before issuing a cert, it verifies you control the domain. This cluster uses the **DNS-01 challenge**:

```
cert-manager calls Route53 API →  Creates TXT record:
                                  _acme-challenge.YOURNAME.eks.ironlabs.online = "abc123"

Let's Encrypt checks that TXT record exists via DNS lookup
Domain ownership confirmed → certificate issued
cert-manager deletes the TXT record
```

cert-manager calls Route53 using the IRSA role you created in the setup step — no AWS credentials stored in the cluster.

### ClusterIssuer

A **ClusterIssuer** is a cluster-wide cert-manager resource that defines how to get certificates: which ACME server (staging vs production), which challenge method, which AWS region. You created two during setup:

- `letsencrypt-staging` — test issuer, no rate limits, certs are not browser-trusted
- `letsencrypt-prod` — real browser-trusted certs, rate limited (5 certs/domain/week)

You reference the issuer by name in your Ingress annotation. cert-manager reads the annotation and does the rest.

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

This creates the `lab2` namespace plus a single nginx webapp. Verify:

```bash
kubectl get pods -n lab2
```

### Step 3 — Create the TLS Ingress

Two things make this different from Lab 1:
1. A `cert-manager.io/cluster-issuer` annotation that triggers automatic certificate issuance
2. A `tls:` block that names the Secret cert-manager will write and NGINX will read

```bash
envsubst < ingress-tls.yaml | kubectl apply -f -
```

The Ingress YAML (already in `ingress-tls.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-tls
  namespace: lab2
  annotations:
    # ── cert-manager integration ────────────────────────────────────────────────
    # This annotation is the trigger. cert-manager watches Ingress resources for it.
    # When found, cert-manager creates a Certificate object and starts the ACME flow.
    # "letsencrypt-prod" is the ClusterIssuer created during setup.
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # ── Force HTTPS ─────────────────────────────────────────────────────────────
    # NGINX will return HTTP 308 (Permanent Redirect) for any HTTP request.
    # Browsers cache 308s, so future visits skip HTTP entirely.
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - YOUR_STUDENT_NAME.eks.ironlabs.online
      # cert-manager creates a Secret with this exact name.
      # NGINX reads TLS cert + key from this Secret.
      # The name here is the contract between cert-manager and NGINX.
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

---

### Step 4 — Watch the certificate being issued

As soon as the Ingress is applied, cert-manager kicks off the ACME flow:

```bash
watch -n5 "kubectl get certificate,certificaterequest -n lab2"
```

What you'll see happening:
1. A `Certificate` object appears with `READY=False, Reason=Issuing`
2. A `CertificateRequest` object appears (the actual CSR)
3. An `Order` + `Challenge` object appear (the ACME order and DNS-01 challenge)
4. cert-manager creates the TXT record in Route53 and waits for Let's Encrypt to verify
5. `READY=True` — cert is issued and stored in the Secret

This takes **30–120 seconds**.

```bash
# See the challenge objects
kubectl get challenge -n lab2

# Detailed status
kubectl describe certificate -n lab2
```

---

### Step 5 — Verify the Secret exists

```bash
kubectl get secret ${STUDENT_NAME}-tls-secret -n lab2
# Should show: kubernetes.io/tls
```

---

### Step 6 — Wait for DNS

While the cert was being issued, external-dns was also creating a DNS record for your hostname. Check it's ready:

```bash
nslookup ${STUDENT_NAME}.eks.ironlabs.online
```

---

### Step 7 — Test HTTPS

```bash
curl https://${STUDENT_NAME}.eks.ironlabs.online
```

Open in a browser — you'll see the padlock icon. Click it and inspect the certificate — Issuer should show **Let's Encrypt**.

---

### Step 8 — Verify HTTP redirects to HTTPS

```bash
# -I shows headers only, -L follows redirects
curl -IL http://${STUDENT_NAME}.eks.ironlabs.online

# First response should be:
# HTTP/1.1 308 Permanent Redirect
# Location: https://YOURNAME.eks.ironlabs.online/
#
# Second response (after following redirect) should be HTTP/2 200
```

---

## Inspect the certificate

```bash
# View what Let's Encrypt issued
kubectl get secret ${STUDENT_NAME}-tls-secret -n lab2 \
  -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 -noout -text \
  | grep -E "Issuer|Subject|Not Before|Not After"
```

---

## Clean up

```bash
envsubst < ingress-tls.yaml | kubectl delete -f -
kubectl delete -f apps.yaml
```

cert-manager will clean up its internal Certificate, CertificateRequest, and Order objects automatically. The Secret gets deleted with the namespace. external-dns detects the deleted Ingress and removes the Route53 DNS records within a minute or two.

> **Run cleanup before starting Lab 3.** Labs 3 and 4 use the same hostname via a Gateway. If the Lab 2 Ingress is still live, it and the Gateway will conflict over `YOURNAME.eks.ironlabs.online` and DNS will be unstable.

---

## Key takeaways

- **TLS termination at the Ingress** keeps your backend pods simple — they receive plain HTTP
- **cert-manager** + **ClusterIssuer** makes certificate management zero-touch
- **DNS-01 challenge** proves domain ownership via Route53, works even before traffic exists
- The **secretName** in the Ingress `tls:` block is the handoff point between cert-manager (writes) and NGINX (reads)
- **308 Permanent Redirect** for HTTP→HTTPS: browsers cache it and skip HTTP on future visits

When you're done, continue to [Lab 3 →](../lab3-gateway-routing/README.md)
