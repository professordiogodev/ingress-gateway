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

## How to do these labs — follow this order

| Step | What | Time |
|------|------|------|
| **1** | Read [`00-intro-2026.md`](00-intro-2026.md) — what a controller is, why Ingress is being retired, the 2026 landscape | ~10 min |
| **2** | **Set up your cluster** with [`setup/README.md`](setup/README.md) — installs the tools you need (`helm`, `eksctl`, …) and all the controllers. **Do this once, before any lab. Nothing in the labs works without it.** | ~10 min |
| **3** | [Lab 1](lab1-ingress-routing/) → [Lab 2](lab2-ingress-https/) → [Lab 3](lab3-gateway-routing/) → [Lab 4](lab4-gateway-https/), in order. Run each lab's cleanup before starting the next one. | |

> **Don't skip step 2.** If you jump straight into Lab 1, `kubectl apply` will either fail or create resources that nothing acts on — no load balancer, no DNS record, no certificate.

## Domain convention

You pick a short name (`yourname`). All your URLs live under:

```
YOURNAME.eks.ironlabs.online          ← main URL
blue.YOURNAME.eks.ironlabs.online     ← blue app (Labs 1, 3)
green.YOURNAME.eks.ironlabs.online    ← green app (Labs 1, 3)
```

DNS records are created **automatically** when you apply your Ingress or Gateway YAML. You never touch Route53 manually.

## What's in the setup

[`setup/README.md`](setup/README.md) walks you through it step by step. In short:

```
setup/
├── README.md              ← START HERE: install tools, set variables, run the scripts below
├── 00-oidc-iam.sh         ← OIDC provider + IAM roles for AWS access
├── 01-install-nginx-ingress.sh
├── 02-install-cert-manager.sh
├── 03-install-external-dns.sh
├── 04-install-gateway-api.sh
└── 05-configure-issuers.sh
```

You'll need `kubectl` and the `aws` CLI already configured against your cluster and account. The setup guide installs `helm` and `eksctl` for you if they're missing.

**Next:** read [`00-intro-2026.md`](00-intro-2026.md), then go to [`setup/README.md`](setup/README.md).
