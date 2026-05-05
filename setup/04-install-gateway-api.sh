#!/usr/bin/env bash
# Instructor only — installs Gateway API CRDs and NGINX Gateway Fabric.
# Gateway API is the next-generation standard for routing in Kubernetes,
# replacing Ingress with a richer, role-oriented model.
set -euo pipefail

GATEWAY_API_VERSION="v1.2.1"

echo "==> Installing Gateway API CRDs (standard channel)..."
kubectl apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "==> Installing NGINX Gateway Fabric via Helm (OCI chart)..."
# The chart is distributed via GitHub Container Registry (OCI), not a Helm repo.
# The GatewayClass "nginx" is created automatically by the chart.
helm upgrade --install nginx-gateway oci://ghcr.io/nginxinc/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --wait --timeout=5m

echo "==> Gateway API + NGINX Gateway Fabric installed."
echo "    Gateway Fabric LoadBalancer hostname:"
kubectl get svc -n nginx-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'; echo
