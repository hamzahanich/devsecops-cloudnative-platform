#!/usr/bin/env bash
set -euo pipefail

echo "=== DevSecOps Platform Health & Status Audit ==="

echo ""
echo "[1] Kubernetes Nodes:"
kubectl get nodes -o wide || echo "[WARN] Unable to reach Kubernetes API."

echo ""
echo "[2] Cilium Tetragon (eBPF Runtime):"
kubectl get daemonset -n kube-system tetragon 2>/dev/null || echo "[WARN] Tetragon daemonset not found."
echo "Active eBPF TracingPolicies:"
kubectl get tracingpolicies.cilium.io -A 2>/dev/null || echo "No TracingPolicies found."

echo ""
echo "[3] Kyverno Admission Controller:"
kubectl get pods -n kyverno 2>/dev/null || echo "[WARN] Kyverno pods not found."
echo "Active ClusterPolicies:"
kubectl get clusterpolicies -o custom-columns=NAME:.metadata.name,ACTION:.spec.validationFailureAction 2>/dev/null || echo "No ClusterPolicies found."

echo ""
echo "[4] Network Security & Dynamic Quarantine:"
echo "Active NetworkPolicies:"
kubectl get networkpolicies -A 2>/dev/null
echo "Quarantined Pods:"
kubectl get pods -A -l security-status=quarantined --no-headers 2>/dev/null || echo "[INFO] No pods currently quarantined."

echo ""
echo "[5] Supply Chain Security:"
KEYS_DIR="$(dirname "$0")/../supply-chain/keys"
if [ -f "$KEYS_DIR/cosign.pub" ]; then
    echo "[INFO] Cosign public key found: $KEYS_DIR/cosign.pub"
    head -n 2 "$KEYS_DIR/cosign.pub"
else
    echo "[WARN] Cosign public key missing in $KEYS_DIR"
fi

echo ""
echo "[6] Observability Stack:"
kubectl get pods -n monitoring 2>/dev/null || echo "[INFO] Monitoring namespace not active."
kubectl get prometheusrule -n monitoring 2>/dev/null || true

echo ""
echo "=== Audit Complete ==="
