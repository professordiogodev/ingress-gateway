#!/usr/bin/env bash
# Installs the NGINX Ingress Controller on your cluster.
# Used by Labs 1 and 2.
set -euo pipefail

: "${CLUSTER_NAME:?Set CLUSTER_NAME first (see setup/README.md Step 0)}"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update ingress-nginx

# The NLB annotations tell AWS to create an internet-facing Network Load Balancer.
# "nlb" = AWS NLB (Layer 4). One NLB will serve all Ingress resources you create.
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --set controller.allowSnippetAnnotations=true \
  --wait --timeout=5m

echo ""
echo "==> NGINX Ingress Controller installed."
echo "    NLB hostname (CNAME target for your DNS records):"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
