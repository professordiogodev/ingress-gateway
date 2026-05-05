#!/usr/bin/env bash
# Creates the Let's Encrypt ClusterIssuers in your cluster.
# A ClusterIssuer defines HOW to get certificates: which ACME server,
# which challenge method, which AWS region for Route53 access.
# Used by Labs 2 and 4.
set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION first (see setup/README.md Step 0)}"

HOSTED_ZONE_ID="Z042372728MB5VI4H04IG"   # ironlabs.online
ACME_EMAIL="finkry@gmail.com"             # Let's Encrypt account email

# ── Staging issuer ─────────────────────────────────────────────────────────────
# Use this first to test your setup. No rate limits, but the certs aren't
# browser-trusted (you'll see a security warning). Good for verifying the
# DNS-01 challenge flow works before burning production cert quota.
echo "==> Creating letsencrypt-staging ClusterIssuer..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
      - dns01:
          route53:
            region: ${AWS_REGION}
            hostedZoneID: ${HOSTED_ZONE_ID}
EOF

# ── Production issuer ─────────────────────────────────────────────────────────
# Issues real, browser-trusted certificates. Rate limited: 5 certs per
# registered domain per week. Don't spam this during testing.
echo "==> Creating letsencrypt-prod ClusterIssuer..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          route53:
            region: ${AWS_REGION}
            hostedZoneID: ${HOSTED_ZONE_ID}
EOF

echo ""
echo "==> ClusterIssuers created. Waiting for ACME registration..."
kubectl wait clusterissuer letsencrypt-staging letsencrypt-prod \
  --for=condition=Ready --timeout=60s

kubectl get clusterissuer
