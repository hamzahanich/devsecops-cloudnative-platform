#!/usr/bin/env bash
set -euo pipefail

IMAGE_TARGET="${1:-secured-app:1.0.0}"
REPORTS_DIR="$(dirname "$0")/reports"
mkdir -p "$REPORTS_DIR"

echo "=== Trivy Security Vulnerability & IaC Scan ==="
echo "Target: $IMAGE_TARGET"

if ! command -v trivy >/dev/null 2>&1; then
    echo "[ERROR] Trivy CLI not found in PATH."
    echo "Install Trivy: https://aquasecurity.github.io/trivy"
    exit 1
fi

echo "[INFO] Scanning container image for HIGH and CRITICAL vulnerabilities..."
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  "$IMAGE_TARGET" || true

echo "[INFO] Exporting JSON report to $REPORTS_DIR/trivy-vuln-report.json..."
trivy image \
  --format json \
  --output "$REPORTS_DIR/trivy-vuln-report.json" \
  "$IMAGE_TARGET"

echo "[INFO] Scanning Kubernetes manifests and IaC configurations..."
trivy config \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  "$(dirname "$0")/../kyverno/policies"

echo "[OK] Trivy scan completed."
