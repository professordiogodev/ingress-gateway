# Cluster Setup — Run Once Before All Labs

This installs everything your personal EKS cluster needs to support Labs 1–4. Run the scripts in order. The whole process takes about 10 minutes.

---

## What you're installing and why

These labs exercise four Kubernetes components that don't come with EKS out of the box:

**NGINX Ingress Controller** — A pod running NGINX that watches `Ingress` resources and acts as a reverse proxy. It's the old standard (now retired — see `00-intro-2026.md`). Labs 1 and 2 use it.

**cert-manager** — A controller that automates TLS certificate lifecycle. It talks to Let's Encrypt on your behalf, proves you own your domain, stores the cert in a Kubernetes Secret, and renews it before it expires. Labs 2 and 4 use it.

**external-dns** — A controller that watches your `Ingress` and `HTTPRoute` resources and automatically creates DNS records in Route53. Without it, you'd have to manually point DNS at your load balancer every time. All labs use it.

**NGINX Gateway Fabric** — The same company's implementation of the Gateway API standard. It watches `Gateway` and `HTTPRoute` resources instead of `Ingress` resources. Labs 3 and 4 use it.

**Let's Encrypt ClusterIssuers** — Two cluster-wide cert-manager objects that tell cert-manager how to get certificates: which ACME server, which challenge method (DNS-01 via Route53). Labs 2 and 4 use them.

---

## Step 0 — Set your variables

Every script reads these. Set them in your shell before running anything.

```bash
# Your chosen name — becomes your DNS subdomain: YOURNAME.eks.ironlabs.online
# Lowercase, no spaces, no dots. Example: alice, bob, carmen
export STUDENT_NAME=yourname

# Your EKS cluster name and region
export CLUSTER_NAME=$(aws eks list-clusters \
  --query "clusters[?contains(@, '${STUDENT_NAME}')] | [0]" \
  --output text)
export AWS_REGION=us-east-1   # change if your cluster is in a different region

# Auto-discovered — don't change these
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export OIDC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query "cluster.identity.oidc.issuer" --output text | cut -d/ -f5)

echo "Cluster:    $CLUSTER_NAME"
echo "Region:     $AWS_REGION"
echo "Account ID: $ACCOUNT_ID"
echo "OIDC ID:    $OIDC_ID"
echo "Your domain: ${STUDENT_NAME}.eks.ironlabs.online"
```

Verify the output looks correct before continuing.

---

## Step 1 — OIDC provider and IAM roles

```bash
bash 00-oidc-iam.sh
```

**What this does:**

*OIDC provider* — Kubernetes pods can prove their identity to AWS using a token signed by the cluster's OIDC endpoint. This script registers that endpoint with AWS IAM so that IAM can verify those tokens. Without this, pods can't assume IAM roles.

*IAM roles* — Creates two roles using IRSA (IAM Roles for Service Accounts):
- `ExternalDNSRole-CLUSTERNAME` — allows external-dns to create records in the `ironlabs.online` Route53 zone
- `CertManagerRole-CLUSTERNAME` — allows cert-manager to create DNS-01 challenge records in the same zone

These roles are scoped tightly: they can only be assumed by the specific service accounts in your cluster, and they can only modify Route53 records in `ironlabs.online`.

---

## Step 2 — NGINX Ingress Controller

```bash
bash 01-install-nginx-ingress.sh
```

**What this does:**

Installs the NGINX Ingress Controller via Helm into the `ingress-nginx` namespace. When it starts, it creates an AWS **Network Load Balancer** (NLB) that receives all traffic for Labs 1 and 2.

The NLB is shared across all your Ingress resources. You don't pay per Ingress — you pay per NLB. That's the cost efficiency of the ingress pattern.

At the end of this script, you'll see the NLB hostname. external-dns will later create CNAMEs pointing to this hostname.

---

## Step 3 — cert-manager

```bash
bash 02-install-cert-manager.sh
```

**What this does:**

Installs cert-manager v1.17 into the `cert-manager` namespace with the IRSA role from Step 1 attached to its service account. This lets cert-manager call the Route53 API to create DNS-01 challenge records without long-lived AWS credentials in the cluster.

cert-manager installs three pods:
- `cert-manager` — the main controller
- `cert-manager-cainjector` — injects CA bundles into webhook configs
- `cert-manager-webhook` — validates cert-manager resources when you apply them

---

## Step 4 — external-dns

```bash
bash 03-install-external-dns.sh
```

**What this does:**

Installs external-dns into the `external-dns` namespace. It watches:
- `Ingress` resources → creates DNS records for hostnames in `spec.rules[].host`
- `HTTPRoute` resources → creates DNS records for hostnames in the Gateway annotation

It only touches records in `ironlabs.online`. With `policy=sync`, it deletes DNS records when the owning Ingress or Gateway is removed — so lab cleanup also cleans up DNS.

---

## Step 5 — Gateway API CRDs and NGINX Gateway Fabric

```bash
bash 04-install-gateway-api.sh
```

**What this does:**

*Gateway API CRDs* — Installs the standard `GatewayClass`, `Gateway`, `HTTPRoute`, and `ReferenceGrant` custom resource definitions. These are the Kubernetes API types — not a controller, just the schema.

*NGINX Gateway Fabric* — The controller that watches those resources and actually configures NGINX. Like the Ingress Controller, it creates its own NLB (separate from the Ingress NLB).

*GatewayClass* — A cluster-wide resource named `nginx` that says "NGINX Gateway Fabric handles Gateways that reference this class." Your Gateway resources will reference it by name.

---

## Step 6 — Let's Encrypt ClusterIssuers

```bash
bash 05-configure-issuers.sh
```

**What this does:**

Creates two `ClusterIssuer` resources in your cluster:

- `letsencrypt-staging` — points at Let's Encrypt's staging ACME server. Use this for testing: no rate limits, but the issued certificates are not trusted by browsers.
- `letsencrypt-prod` — points at Let's Encrypt's production ACME server. Issues real, browser-trusted certs. Rate limited to 5 certificates per registered domain per week.

Both use **DNS-01 challenge** via Route53: cert-manager creates a TXT record in Route53 to prove domain ownership, Let's Encrypt verifies it, then the TXT record is deleted.

---

## Verify everything is running

```bash
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
kubectl get pods -n external-dns
kubectl get pods -n nginx-gateway
kubectl get clusterissuer
kubectl get gatewayclass
```

All pods should be `Running`. Both ClusterIssuers should show `READY=True`.

---

## Troubleshooting

**external-dns crashes on startup**
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```
Check that the IAM role ARN in the service account annotation is correct and the OIDC provider was registered.

**cert-manager ClusterIssuer stays `READY=False`**
```bash
kubectl describe clusterissuer letsencrypt-prod
```
Usually a Route53 permission issue. Verify the `CertManagerRole` has the correct trust policy for your cluster's OIDC ID.

**NGINX Ingress Controller pod is Pending**
```bash
kubectl describe pod -n ingress-nginx -l app.kubernetes.io/component=controller
```
Likely a node resource issue or missing IAM permissions to create the NLB. Check your node group IAM role has the AWS load balancer controller policies.

---

Once all six steps complete successfully, open [Lab 1](../lab1-ingress-routing/README.md).
