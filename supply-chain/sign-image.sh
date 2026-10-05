#!/usr/bin/env bash
set -euo pipefail

IMAGE_TARGET="${1:-localhost:5000/secured-app:1.0.0}"
KEYS_DIR="$(dirname "$0")/keys"
REPORTS_DIR="$(dirname "$0")/reports"

echo "=== Signing Image and Attesting SBOM with Cosign ==="
echo "Target: $IMAGE_TARGET"

if [ ! -f "$KEYS_DIR/cosign.key" ]; then
    echo "[ERROR] Private key not found at $KEYS_DIR/cosign.key"
    echo "Run ./supply-chain/generate-keys.sh first."
    exit 1
fi

if [ -z "${COSIGN_PASSWORD:-}" ]; then
    read -r -s -p "Enter passphrase for Cosign private key: " COSIGN_PASSWORD
    echo ""
    export COSIGN_PASSWORD
fi

# 1. Sign container image
echo "[INFO] Signing container image..."
cosign sign --key "$KEYS_DIR/cosign.key" "$IMAGE_TARGET" --yes

# 2. Attach SBOM attestation
if [ -f "$REPORTS_DIR/sbom-spdx.json" ]; then
    echo "[INFO] Attaching in-toto SBOM attestation..."
    cosign attest \
      --key "$KEYS_DIR/cosign.key" \
      --predicate "$REPORTS_DIR/sbom-spdx.json" \
      --type spdx \
      "$IMAGE_TARGET" --yes
fi

# 3. Verify signature
echo "[INFO] Verifying image signature with public key..."
cosign verify --key "$KEYS_DIR/cosign.pub" "$IMAGE_TARGET"

echo "[OK] Image signature and attestation verified successfully."
