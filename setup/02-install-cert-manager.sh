#!/usr/bin/env bash
# Instructor only — installs cert-manager with IRSA so it can solve DNS-01 challenges
# via Route53 without needing long-lived AWS credentials.
set -euo pipefail

ACCOUNT_ID="686699774218"
CLUSTER_NAME="spot-eks-lab-test"
CERT_MANAGER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/CertManagerRole-${CLUSTER_NAME}"

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.2 \
  --set crds.enabled=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${CERT_MANAGER_ROLE_ARN}" \
  --wait --timeout=5m

echo "==> cert-manager installed."
kubectl get pods -n cert-manager
