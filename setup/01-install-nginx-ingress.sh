#!/usr/bin/env bash
# Instructor only — installs the NGINX Ingress Controller via Helm.
# This creates a Network Load Balancer (NLB) on AWS that all students share.
set -euo pipefail

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --set controller.allowSnippetAnnotations=true \
  --wait --timeout=5m

echo "==> NGINX Ingress Controller installed."
echo "    LoadBalancer hostname:"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
