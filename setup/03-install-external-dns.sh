#!/usr/bin/env bash
# Instructor only — installs external-dns with IRSA.
# external-dns watches Ingress and HTTPRoute resources and automatically
# creates/updates DNS records in Route53 for ironlabs.online.
set -euo pipefail

ACCOUNT_ID="686699774218"
CLUSTER_NAME="spot-eks-lab-test"
EXTDNS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/ExternalDNSRole-${CLUSTER_NAME}"
HOSTED_ZONE_ID="Z042372728MB5VI4H04IG"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --set provider.name=aws \
  --set "env[0].name=AWS_DEFAULT_REGION" \
  --set "env[0].value=us-east-1" \
  --set "sources[0]=ingress" \
  --set "sources[1]=service" \
  --set "sources[2]=gateway-httproute" \
  --set "domainFilters[0]=ironlabs.online" \
  --set policy=upsert-only \
  --set registry=txt \
  --set txtOwnerId="${HOSTED_ZONE_ID}" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EXTDNS_ROLE_ARN}" \
  --wait --timeout=5m

echo "==> external-dns installed."
kubectl get pods -n external-dns
