#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing Envoy Gateway"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.6.0 \
  --namespace envoy-gateway-system \
  --create-namespace

echo "==> Waiting for Envoy Gateway"
kubectl rollout status deployment/envoy-gateway \
  -n envoy-gateway-system \
  --timeout=180s

echo "==> Installing Prometheus"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "$ROOT_DIR/prometheus-values.yaml"

echo "==> Deploying application and Gateway"
kubectl apply -k "$ROOT_DIR/k8s"

echo "==> Deploying Filebeat"
kubectl apply -f "$ROOT_DIR/logging/filebeat.yaml"

echo "==> Removing control-plane taint for single-node cluster"
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

echo "==> Done"
kubectl get pods -A
