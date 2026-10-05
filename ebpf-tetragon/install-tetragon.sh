#!/usr/bin/env bash
set -euo pipefail

echo "=== Deploying Cilium Tetragon (eBPF Runtime Defense) ==="

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium

kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -

echo "[INFO] Installing Tetragon daemonset..."
helm upgrade --install tetragon cilium/tetragon \
  --namespace kube-system \
  -f "$(dirname "$0")/values-tetragon.yaml"

echo "[INFO] Waiting for Tetragon rollout..."
kubectl rollout status daemonset/tetragon -n kube-system --timeout=120s || true

echo "[INFO] Applying eBPF TracingPolicies..."
kubectl apply -f "$(dirname "$0")/policies/"

echo "[OK] Tetragon and eBPF TracingPolicies successfully applied."
kubectl get tracingpolicies.cilium.io -A
