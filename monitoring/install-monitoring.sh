#!/usr/bin/env bash
set -euo pipefail

echo "=== Deploying Prometheus & Grafana Monitoring Stack ==="

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community

echo "[INFO] Deploying kube-prometheus-stack..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "$(dirname "$0")/prometheus/values-prometheus.yaml"

echo "[INFO] Applying DevSecOps PrometheusRule alerts..."
kubectl apply -f "$(dirname "$0")/prometheus/alerts-devsecops.yaml"

echo "[INFO] Loading Grafana DevSecOps dashboard configmap..."
kubectl create configmap devsecops-dashboard \
  --from-file="$(dirname "$0")/grafana/dashboards/devsecops-dashboard.json" \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap devsecops-dashboard -n monitoring grafana_dashboard=1 --overwrite

echo "[OK] Monitoring stack deployed."
echo "Port-forward Grafana: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
