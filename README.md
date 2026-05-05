# EKS Ingress & Gateway API Labs

Four hands-on labs covering Kubernetes HTTP routing — from the technology the industry is migrating away from, to where everything is going.

## Who this is for

Students who have their own EKS cluster already running. The instructor will walk through cluster creation separately. These labs start from "cluster exists, nothing else installed."

## What you'll build

By the end you'll have gone through both sides of the biggest Kubernetes networking migration happening right now:

| Lab | Topic | Your URL |
|-----|-------|----------|
| [Lab 1](lab1-ingress-routing/) | Ingress: path & subdomain routing | `http://YOURNAME.eks.ironlabs.online/blue` |
| [Lab 2](lab2-ingress-https/) | Ingress: HTTPS | `https://YOURNAME.eks.ironlabs.online` |
| [Lab 3](lab3-gateway-routing/) | Gateway API: path & subdomain routing | `http://YOURNAME.eks.ironlabs.online/blue` |
| [Lab 4](lab4-gateway-https/) | Gateway API: HTTPS | `https://YOURNAME.eks.ironlabs.online` |

## Before the first lab: set up your cluster

Run the scripts in [`setup/`](setup/) once. They install everything your cluster needs to support all four labs:

```
setup/
├── README.md              ← start here, explains what each component is
├── 00-oidc-iam.sh         ← OIDC provider + IAM roles for AWS access
├── 01-install-nginx-ingress.sh
├── 02-install-cert-manager.sh
├── 03-install-external-dns.sh
├── 04-install-gateway-api.sh
└── 05-configure-issuers.sh
```

## Domain convention

You pick a short name (`yourname`). All your URLs live under:

```
YOURNAME.eks.ironlabs.online          ← main URL
blue.YOURNAME.eks.ironlabs.online     ← blue app (Labs 1, 3)
green.YOURNAME.eks.ironlabs.online    ← green app (Labs 1, 3)
```

DNS records are created **automatically** when you apply your Ingress or Gateway YAML. You never touch Route53 manually.

## Tools you need

| Tool | Why |
|------|-----|
| `kubectl` | Configured against your EKS cluster |
| `aws` CLI | Configured with your AWS credentials |
| `helm` | Installs the controllers |
| `eksctl` | Creates the OIDC provider |
| `envsubst` | Substitutes `$STUDENT_NAME` in YAML (part of `gettext`) |

Check all four are available before starting:
```bash
kubectl version --client && aws sts get-caller-identity && helm version --short && eksctl version && envsubst --version
```

## Start here

```
00-intro-2026.md   ← context: what is a controller, why Ingress is dying, 2026 landscape
setup/README.md    ← install everything on your cluster (run once, takes ~10 min)
lab1-ingress-routing/README.md
```
