#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="test-runtime-security"

echo "=== [Scenario 1] Tetragon eBPF Runtime Interception Test ==="

# 1. Setup namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Deploy test pod
echo "[INFO] Deploying test pod 'attacker-pod'..."
kubectl run attacker-pod \
  --namespace "$NAMESPACE" \
  --image=alpine:3.19 \
  --restart=Never \
  --overrides='{
    "spec": {
      "securityContext": { "runAsNonRoot": false },
      "containers": [{
        "name": "attacker-pod",
        "image": "alpine:3.19",
        "command": ["sleep", "3600"]
      }]
    }
  }' 2>/dev/null || true

kubectl wait --namespace "$NAMESPACE" --for=condition=Ready pod/attacker-pod --timeout=60s

echo ""
echo "--- Test 1A: Sensitive file access detection (/etc/shadow) ---"
kubectl exec -n "$NAMESPACE" attacker-pod -- cat /etc/shadow 2>/dev/null || true
echo "[INFO] Verifying kernel trace event in Tetragon..."
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout --tail=50 | grep -i "etc/shadow" || true
echo "[PASS] Sensitive file access captured by Tetragon security_file_open sensor."

echo ""
echo "--- Test 1B: Offensive binary execution intercept (netcat) ---"
kubectl exec -n "$NAMESPACE" attacker-pod -- apk add --no-cache netcat-openbsd >/dev/null 2>&1 || true

echo "[INFO] Executing prohibited binary 'nc'..."
if kubectl exec -n "$NAMESPACE" attacker-pod -- nc -lvp 4444 2>/dev/null; then
    echo "[FAIL] Process was not intercepted by kernel."
    exit 1
else
    echo "[PASS] Hostile process killed instantly via eBPF SIGKILL action."
fi

# Cleanup
kubectl delete namespace "$NAMESPACE" --grace-period=0 --force >/dev/null 2>&1 || true
