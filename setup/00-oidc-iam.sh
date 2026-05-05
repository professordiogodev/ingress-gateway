#!/usr/bin/env bash
# Run once before any lab.
# Creates the OIDC provider and IAM roles that allow cert-manager and
# external-dns to call AWS APIs (Route53) without long-lived credentials.
set -euo pipefail

# ── Require variables set in setup/README.md Step 0 ──────────────────────────
: "${CLUSTER_NAME:?Set CLUSTER_NAME first (see setup/README.md Step 0)}"
: "${AWS_REGION:?Set AWS_REGION first}"
: "${ACCOUNT_ID:?Set ACCOUNT_ID first}"
: "${OIDC_ID:?Set OIDC_ID first}"

OIDC_ISSUER="oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}"
HOSTED_ZONE_ID="Z042372728MB5VI4H04IG"   # ironlabs.online — provided by instructor

echo "==> Cluster:  $CLUSTER_NAME"
echo "==> Region:   $AWS_REGION"
echo "==> Account:  $ACCOUNT_ID"
echo "==> OIDC ID:  $OIDC_ID"
echo ""

# ── 1. Register the OIDC provider ─────────────────────────────────────────────
# This lets AWS IAM trust tokens issued by your cluster's OIDC endpoint.
# Pods that have an IRSA-annotated service account can then assume IAM roles.
echo "==> Registering OIDC provider for cluster ${CLUSTER_NAME}..."
eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region  "$AWS_REGION" \
  --approve

# ── 2. IAM policy for external-dns ────────────────────────────────────────────
# Allows: list zones (read-only) + create/update records in ironlabs.online only.
echo "==> Creating IAM policy for external-dns..."
cat > /tmp/external-dns-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["route53:ChangeResourceRecordSets"],
      "Resource": ["arn:aws:route53:::hostedzone/${HOSTED_ZONE_ID}"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource"
      ],
      "Resource": ["*"]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name "ExternalDNSPolicy-${CLUSTER_NAME}" \
  --policy-document file:///tmp/external-dns-policy.json \
  --no-cli-pager 2>/dev/null || echo "  (policy already exists, continuing)"

# ── 3. IAM role for external-dns (IRSA) ───────────────────────────────────────
# Trust policy: only the external-dns service account in your cluster can assume this role.
echo "==> Creating IAM role for external-dns..."
cat > /tmp/external-dns-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_ISSUER}:sub": "system:serviceaccount:external-dns:external-dns",
        "${OIDC_ISSUER}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF

aws iam create-role \
  --role-name "ExternalDNSRole-${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/external-dns-trust.json \
  --no-cli-pager 2>/dev/null || echo "  (role already exists, continuing)"

aws iam attach-role-policy \
  --role-name "ExternalDNSRole-${CLUSTER_NAME}" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ExternalDNSPolicy-${CLUSTER_NAME}" \
  --no-cli-pager

# ── 4. IAM policy for cert-manager ────────────────────────────────────────────
# Allows: create/delete TXT records for ACME DNS-01 challenges in ironlabs.online.
echo "==> Creating IAM policy for cert-manager..."
cat > /tmp/cert-manager-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/${HOSTED_ZONE_ID}"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ListHostedZonesByName",
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name "CertManagerPolicy-${CLUSTER_NAME}" \
  --policy-document file:///tmp/cert-manager-policy.json \
  --no-cli-pager 2>/dev/null || echo "  (policy already exists, continuing)"

# ── 5. IAM role for cert-manager (IRSA) ───────────────────────────────────────
echo "==> Creating IAM role for cert-manager..."
cat > /tmp/cert-manager-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_ISSUER}:sub": "system:serviceaccount:cert-manager:cert-manager",
        "${OIDC_ISSUER}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF

aws iam create-role \
  --role-name "CertManagerRole-${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/cert-manager-trust.json \
  --no-cli-pager 2>/dev/null || echo "  (role already exists, continuing)"

aws iam attach-role-policy \
  --role-name "CertManagerRole-${CLUSTER_NAME}" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CertManagerPolicy-${CLUSTER_NAME}" \
  --no-cli-pager

echo ""
echo "==> Done. IAM roles created:"
echo "    arn:aws:iam::${ACCOUNT_ID}:role/ExternalDNSRole-${CLUSTER_NAME}"
echo "    arn:aws:iam::${ACCOUNT_ID}:role/CertManagerRole-${CLUSTER_NAME}"
