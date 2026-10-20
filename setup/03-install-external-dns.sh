#!/usr/bin/env bash
# Installs external-dns with the IRSA role from step 00 attached.
# Watches Ingress and HTTPRoute resources and auto-creates DNS records in Route53.
# Used by all labs.
set -euo pipefail

: "${CLUSTER_NAME:?Set CLUSTER_NAME first (see setup/README.md Step 0)}"
: "${ACCOUNT_ID:?Set ACCOUNT_ID first}"
: "${AWS_REGION:?Set AWS_REGION first}"

EXTDNS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/ExternalDNSRole-${CLUSTER_NAME}"
HOSTED_ZONE_ID="Z042372728MB5VI4H04IG"   # ironlabs.online

# external-dns watches HTTPRoutes, so the Gateway API CRDs must exist first —
# otherwise it hangs forever waiting for the HTTPRoute informer to sync.
# 04-install-gateway-api.sh re-applies the same CRDs, which is harmless.
kubectl apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns

helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --set provider.name=aws \
  --set "env[0].name=AWS_DEFAULT_REGION" \
  --set "env[0].value=${AWS_REGION}" \
  --set "sources[0]=ingress" \
  --set "sources[1]=service" \
  --set "sources[2]=gateway-httproute" \
  --set "domainFilters[0]=ironlabs.online" \
  --set policy=sync \
  --set registry=txt \
  --set txtOwnerId="${CLUSTER_NAME}" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EXTDNS_ROLE_ARN}" \
  --wait --timeout=5m

echo ""
echo "==> external-dns installed."
kubectl get pods -n external-dns
