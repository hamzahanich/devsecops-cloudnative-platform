#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Deploying Cloud-Native DevSecOps Platform ==="

# 1. k3s check
if ! command -v kubectl >/dev/null 2>&1 || ! kubectl get nodes >/dev/null 2>&1; then
    echo "[INFO] Initializing k3s cluster..."
    bash "$BASE_DIR/cluster/install-k3s.sh"
else
    echo "[INFO] Existing Kubernetes cluster detected."
fi

# 2. Helm
if ! command -v helm >/dev/null 2>&1; then
    echo "[INFO] Installing Helm 3..."
    curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 3. Cilium Tetragon eBPF
echo "[INFO] Deploying Cilium Tetragon and TracingPolicies..."
bash "$BASE_DIR/ebpf-tetragon/install-tetragon.sh"

# 4. Kyverno Admission Controller
echo "[INFO] Deploying Kyverno Zero-Trust policies..."
bash "$BASE_DIR/kyverno/install-kyverno.sh"

# 5. Supply Chain Keys
echo "[INFO] Initializing Cosign verification keys..."
bash "$BASE_DIR/supply-chain/generate-keys.sh"

# 6. Network Security & Quarantine
echo "[INFO] Configuring NetworkPolicies and Auto-Quarantine controller..."
kubectl create namespace secured-apps --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$BASE_DIR/network-security/default-deny-all.yaml"
kubectl apply -f "$BASE_DIR/network-security/allow-dns-and-monitoring.yaml"
kubectl apply -f "$BASE_DIR/network-security/auto-quarantine/quarantine-networkpolicy.yaml"

kubectl create configmap quarantine-controller-script \
  --from-file="$BASE_DIR/network-security/auto-quarantine/quarantine-controller.py" \
  -n kube-system \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$BASE_DIR/network-security/auto-quarantine/quarantine-deployment.yaml"

# 7. Monitoring
echo "[INFO] Deploying Prometheus and Grafana stack..."
bash "$BASE_DIR/monitoring/install-monitoring.sh"

echo ""
echo "[OK] DevSecOps platform deployment complete."
echo "Use 'make status' or './scripts/status.sh' to inspect components."
