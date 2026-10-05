#!/usr/bin/env bash
set -euo pipefail

KEYS_DIR="$(dirname "$0")/keys"
mkdir -p "$KEYS_DIR"

echo "=== Generating Cosign ECDSA Key Pair ==="

if ! command -v cosign >/dev/null 2>&1; then
    echo "[ERROR] cosign binary not found in PATH."
    echo "Install cosign: https://github.com/sigstore/cosign"
    exit 1
fi

if [ -f "$KEYS_DIR/cosign.key" ]; then
    echo "[INFO] Private key already exists at $KEYS_DIR/cosign.key"
    echo "[INFO] Public key:"
    cat "$KEYS_DIR/cosign.pub"
    exit 0
fi

if [ -z "${COSIGN_PASSWORD:-}" ]; then
    read -r -s -p "Enter passphrase for private key (or press enter for empty): " COSIGN_PASSWORD
    echo ""
    export COSIGN_PASSWORD
fi

cd "$KEYS_DIR"
cosign generate-key-pair

echo "[OK] Keypair generated successfully in $KEYS_DIR"
cat "$KEYS_DIR/cosign.pub"
