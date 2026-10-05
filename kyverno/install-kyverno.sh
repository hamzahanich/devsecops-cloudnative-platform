#!/usr/bin/env bash
set -euo pipefail

echo "=== Deploying Kyverno Admission Controller ==="

helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update kyverno

echo "[INFO] Installing Kyverno Helm chart..."
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  -f "$(dirname "$0")/values-kyverno.yaml"

echo "[INFO] Waiting for Kyverno admission controller deployment..."
kubectl rollout status deployment/kyverno-admission-controller -n kyverno --timeout=180s

echo "[INFO] Applying Zero-Trust ClusterPolicies..."
kubectl apply -f "$(dirname "$0")/policies/"

echo "[OK] Kyverno and Zero-Trust policies deployed."
kubectl get clusterpolicies
