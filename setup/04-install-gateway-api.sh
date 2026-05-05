#!/usr/bin/env bash
# Installs the Gateway API CRDs and NGINX Gateway Fabric.
# Used by Labs 3 and 4.
set -euo pipefail

GATEWAY_API_VERSION="v1.2.1"

# ── Gateway API CRDs ──────────────────────────────────────────────────────────
# These are the standard Kubernetes resource definitions: GatewayClass, Gateway,
# HTTPRoute, GRPCRoute, ReferenceGrant, etc. They're the API spec, not a controller.
# Every Gateway API implementation (NGINX, Envoy, Cilium, Istio) uses the same CRDs.
echo "==> Installing Gateway API CRDs (standard channel, ${GATEWAY_API_VERSION})..."
kubectl apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

# ── NGINX Gateway Fabric ──────────────────────────────────────────────────────
# This is the controller that implements Gateway API using NGINX.
# Distributed via GitHub Container Registry (OCI), not a traditional Helm repo.
# The chart automatically creates a GatewayClass named "nginx".
echo "==> Installing NGINX Gateway Fabric..."
helm upgrade --install nginx-gateway oci://ghcr.io/nginxinc/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --wait --timeout=5m

echo ""
echo "==> Gateway API + NGINX Gateway Fabric installed."
echo "    GatewayClass:"
kubectl get gatewayclass
echo ""
echo "    Gateway Fabric NLB hostname:"
kubectl get svc -n nginx-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'; echo
