#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="test-zero-trust"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "=== [Scenario 2] Kyverno Zero-Trust Admission Tests ==="

echo ""
echo "--- Test 2A: Reject Root Container (UID 0) ---"
if cat <<EOF | kubectl apply -n "$NAMESPACE" -f - 2>&1 | grep -q "disallow-root-user"; then
apiVersion: v1
kind: Pod
metadata:
  name: bad-root-pod
spec:
  containers:
    - name: app
      image: alpine:3.19.1
      command: ["sleep", "3600"]
      securityContext:
        runAsNonRoot: false
        runAsUser: 0
EOF
    echo "[PASS] Kyverno admission webhook rejected root user container."
else
    echo "[FAIL] Pod with root user was admitted."
fi

echo ""
echo "--- Test 2B: Reject Writable Root Filesystem ---"
if cat <<EOF | kubectl apply -n "$NAMESPACE" -f - 2>&1 | grep -q "readonly-root-filesystem"; then
apiVersion: v1
kind: Pod
metadata:
  name: bad-fs-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
  containers:
    - name: app
      image: alpine:3.19.1
      command: ["sleep", "3600"]
      securityContext:
        readOnlyRootFilesystem: false
EOF
    echo "[PASS] Kyverno admission webhook rejected writable root filesystem."
else
    echo "[FAIL] Pod with writable filesystem was admitted."
fi

echo ""
echo "--- Test 2C: Reject ':latest' Image Tag ---"
if cat <<EOF | kubectl apply -n "$NAMESPACE" -f - 2>&1 | grep -q "disallow-latest-tag"; then
apiVersion: v1
kind: Pod
metadata:
  name: bad-tag-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
  containers:
    - name: app
      image: nginx:latest
      securityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF
    echo "[PASS] Kyverno admission webhook rejected unpinned/latest tag."
else
    echo "[FAIL] Pod with latest image tag was admitted."
fi

echo ""
echo "--- Test 2D: Deploy Fully Compliant Pod ---"
cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
  containers:
    - name: app
      image: alpine:3.19.1
      command: ["sleep", "3600"]
      securityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF

kubectl wait --namespace "$NAMESPACE" --for=condition=Ready pod/compliant-pod --timeout=60s
echo "[PASS] Compliant Pod successfully admitted and running."

# Cleanup
kubectl delete namespace "$NAMESPACE" --grace-period=0 --force >/dev/null 2>&1 || true
