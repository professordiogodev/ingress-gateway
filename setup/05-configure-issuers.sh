#!/usr/bin/env bash
# Instructor only — creates the Let's Encrypt ClusterIssuers.
# ClusterIssuers are cluster-wide resources; students reference them by name
# in their Ingress or Certificate resources without needing to create their own.
set -euo pipefail

REGION="us-east-1"
HOSTED_ZONE_ID="Z042372728MB5VI4H04IG"

echo "==> Creating Let's Encrypt staging ClusterIssuer (for testing)..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: finkry@gmail.com
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
      - dns01:
          route53:
            region: ${REGION}
            hostedZoneID: ${HOSTED_ZONE_ID}
EOF

echo "==> Creating Let's Encrypt production ClusterIssuer..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: finkry@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          route53:
            region: ${REGION}
            hostedZoneID: ${HOSTED_ZONE_ID}
EOF

echo "==> ClusterIssuers created:"
kubectl get clusterissuer
