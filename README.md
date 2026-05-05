# EKS Ingress & Gateway API Labs

Four hands-on labs for students who already have an EKS cluster running.

## Lab Overview

| Lab | Topic | Key concepts |
|-----|-------|--------------|
| [Lab 1](lab1-ingress-routing/) | Ingress: path & subdomain routing | Ingress, IngressClass, external-dns |
| [Lab 2](lab2-ingress-https/) | Ingress: HTTPS | cert-manager, Let's Encrypt, DNS-01, ClusterIssuer |
| [Lab 3](lab3-gateway-routing/) | Gateway API: path & subdomain routing | GatewayClass, Gateway, HTTPRoute |
| [Lab 4](lab4-gateway-https/) | Gateway API: HTTPS | Gateway TLS listeners, Certificate, RequestRedirect |

## Domain convention

Every student gets their own subdomain under `ironlabs.online`:

```
yourname.eks.ironlabs.online         ← your main URL (Labs 1, 2, 4)
blue.yourname.eks.ironlabs.online    ← subdomain routing (Labs 1, 3)
green.yourname.eks.ironlabs.online   ← subdomain routing (Labs 1, 3)
```

DNS records are created **automatically** by external-dns when you apply your Ingress or Gateway resources. You don't touch Route53 manually.

## What students need

- `kubectl` configured against the shared EKS cluster
- `helm` CLI
- `envsubst` (part of `gettext`, pre-installed on most Linux/Mac)
- Your name set as an environment variable: `export STUDENT_NAME=yourname`

**Students do NOT need to install any controllers.** The instructor pre-installs everything in the `setup/` directory.

---

## Instructor setup (run once before the labs)

```bash
cd setup/
chmod +x *.sh

bash 00-oidc-iam.sh          # OIDC provider + IAM roles for IRSA
bash 01-install-nginx-ingress.sh   # NGINX Ingress Controller
bash 02-install-cert-manager.sh    # cert-manager
bash 03-install-external-dns.sh    # external-dns (Route53)
bash 04-install-gateway-api.sh     # Gateway API CRDs + NGINX Gateway Fabric
bash 05-configure-issuers.sh       # Let's Encrypt ClusterIssuers
```

### What each component does (share with students)

**NGINX Ingress Controller** — A pod running NGINX that watches Kubernetes `Ingress` resources and configures itself as a reverse proxy. One NLB serves all students.

**cert-manager** — Automates TLS certificate lifecycle: requests certs from Let's Encrypt, stores them as Kubernetes Secrets, and renews them before expiry.

**external-dns** — Watches `Ingress` and `HTTPRoute` resources and automatically creates/updates DNS records in Route53. Students never touch Route53 directly.

**Gateway API CRDs** — Custom Resource Definitions that add `Gateway`, `HTTPRoute`, `GatewayClass`, etc. to the cluster. These are the standard Kubernetes API types, not vendor-specific.

**NGINX Gateway Fabric** — An implementation of the Gateway API standard using NGINX. It watches `Gateway` and `HTTPRoute` resources and provisions a second NLB (separate from the Ingress Controller NLB).

**Let's Encrypt ClusterIssuers** — Two cluster-wide cert-manager resources: `letsencrypt-staging` (for testing, no rate limits) and `letsencrypt-prod` (real certs, browser-trusted). Students reference these by name — they don't create their own issuers.

---

## Cluster info

- **Cluster:** `spot-eks-lab-test` (us-east-1)
- **Hosted zone:** `ironlabs.online` (Z042372728MB5VI4H04IG)
- **OIDC provider:** IRSA-enabled for external-dns and cert-manager
