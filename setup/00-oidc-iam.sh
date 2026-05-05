#!/usr/bin/env bash
# Instructor only — run once before students join.
# Creates the OIDC provider for IRSA, plus IAM roles for external-dns and cert-manager.
set -euo pipefail

CLUSTER_NAME="spot-eks-lab-test"
REGION="us-east-1"
ACCOUNT_ID="686699774218"
OIDC_ID="509AFD3A77F672EE464B27FC8679B09A"
OIDC_ISSUER="oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
HOSTED_ZONE_ID="Z042372728MB5VI4H04IG"

echo "==> Registering OIDC provider for cluster ${CLUSTER_NAME}..."
OIDC_URL=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query "cluster.identity.oidc.issuer" --output text)

# Associate OIDC provider if not already done
eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --approve

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
  --no-cli-pager 2>/dev/null || echo "Policy already exists, skipping."

echo "==> Creating IAM role for external-dns (IRSA)..."
cat > /tmp/external-dns-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
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
    }
  ]
}
EOF

aws iam create-role \
  --role-name "ExternalDNSRole-${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/external-dns-trust.json \
  --no-cli-pager 2>/dev/null || echo "Role already exists, skipping."

aws iam attach-role-policy \
  --role-name "ExternalDNSRole-${CLUSTER_NAME}" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ExternalDNSPolicy-${CLUSTER_NAME}" \
  --no-cli-pager

echo "==> Creating IAM policy for cert-manager (Route53 DNS-01)..."
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
  --no-cli-pager 2>/dev/null || echo "Policy already exists, skipping."

echo "==> Creating IAM role for cert-manager (IRSA)..."
cat > /tmp/cert-manager-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
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
    }
  ]
}
EOF

aws iam create-role \
  --role-name "CertManagerRole-${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/cert-manager-trust.json \
  --no-cli-pager 2>/dev/null || echo "Role already exists, skipping."

aws iam attach-role-policy \
  --role-name "CertManagerRole-${CLUSTER_NAME}" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CertManagerPolicy-${CLUSTER_NAME}" \
  --no-cli-pager

echo "==> IAM setup complete."
echo "    ExternalDNS role ARN: arn:aws:iam::${ACCOUNT_ID}:role/ExternalDNSRole-${CLUSTER_NAME}"
echo "    CertManager role ARN: arn:aws:iam::${ACCOUNT_ID}:role/CertManagerRole-${CLUSTER_NAME}"
