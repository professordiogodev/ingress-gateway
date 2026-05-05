#!/usr/bin/env bash
# Installs cert-manager with the IRSA role from step 00 attached.
# Used by Labs 2 and 4.
set -euo pipefail

: "${CLUSTER_NAME:?Set CLUSTER_NAME first (see setup/README.md Step 0)}"
: "${ACCOUNT_ID:?Set ACCOUNT_ID first}"

CERT_MANAGER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/CertManagerRole-${CLUSTER_NAME}"

helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

# crds.enabled=true installs the cert-manager CRDs as part of the Helm chart.
# The serviceAccount annotation wires up IRSA so cert-manager can call Route53
# without any AWS credentials stored in the cluster.
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.2 \
  --set crds.enabled=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${CERT_MANAGER_ROLE_ARN}" \
  --wait --timeout=5m

echo ""
echo "==> cert-manager installed."
kubectl get pods -n cert-manager
