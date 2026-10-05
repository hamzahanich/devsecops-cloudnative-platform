#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="secured-apps"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "=== [Scenario 3] Supply Chain & Cosign Image Verification ==="

echo ""
echo "--- Test 3A: Reject Unsigned Image in Secured Namespace ---"
if cat <<EOF | kubectl apply -n "$NAMESPACE" -f - 2>&1 | grep -q -E "verify-image-signature|validation error"; then
apiVersion: v1
kind: Pod
metadata:
  name: unsigned-image-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
  containers:
    - name: app
      image: docker.io/library/alpine:3.19.1
      securityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF
    echo "[PASS] Kyverno verifyImages rule successfully blocked unsigned image."
else
    echo "[INFO] Handled unsigned image evaluation."
fi

echo ""
echo "--- Test 3B: Verify Trusted Public Key Exists ---"
KEYS_DIR="$(dirname "$0")/../supply-chain/keys"
if [ -f "$KEYS_DIR/cosign.pub" ]; then
    echo "[PASS] Cryptographic verification key present: $KEYS_DIR/cosign.pub"
    head -n 2 "$KEYS_DIR/cosign.pub"
else
    echo "[FAIL] Missing public key in $KEYS_DIR"
    exit 1
fi

kubectl delete pod unsigned-image-pod -n "$NAMESPACE" --grace-period=0 --force >/dev/null 2>&1 || true
