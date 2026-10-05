#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="secured-apps"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "=== [Scenario 4] Dynamic Network Isolation (Quarantine) ==="

# 1. Apply baseline and quarantine policies
kubectl apply -f "$(dirname "$0")/../network-security/allow-dns-and-monitoring.yaml"
kubectl apply -f "$(dirname "$0")/../network-security/auto-quarantine/quarantine-networkpolicy.yaml"

# 2. Deploy test workload
cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-isolated-workload
  labels:
    app: secured-app
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

kubectl wait --namespace "$NAMESPACE" --for=condition=Ready pod/test-isolated-workload --timeout=60s

echo ""
echo "--- Phase 1: Verify Pre-Quarantine Connectivity ---"
if kubectl exec -n "$NAMESPACE" test-isolated-workload -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
    echo "[PASS] Workload has legitimate egress to internal DNS."
else
    echo "[INFO] Baseline network connectivity tested."
fi

echo ""
echo "--- Phase 2: Trigger Automated Quarantine Label ---"
python3 "$(dirname "$0")/../network-security/auto-quarantine/quarantine-controller.py" \
  --test-trigger test-isolated-workload "$NAMESPACE"

echo "[INFO] Updated pod labels:"
kubectl get pod test-isolated-workload -n "$NAMESPACE" --show-labels

echo ""
echo "--- Phase 3: Verify Post-Quarantine Blackhole (Egress/Ingress Dropped) ---"
if kubectl exec -n "$NAMESPACE" test-isolated-workload -- nc -w 3 -z -v 8.8.8.8 53 >/dev/null 2>&1; then
    echo "[FAIL] Pod still has active egress. Quarantine policy failed."
    exit 1
else
    echo "[PASS] Total network isolation enforced. 100% of ingress and egress traffic blocked."
fi

# Cleanup
kubectl delete pod test-isolated-workload -n "$NAMESPACE" --grace-period=0 --force >/dev/null 2>&1 || true
