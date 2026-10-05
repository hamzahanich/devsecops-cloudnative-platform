#!/usr/bin/env bash
set -euo pipefail

IMAGE_TARGET="${1:-secured-app:1.0.0}"
REPORTS_DIR="$(dirname "$0")/reports"
mkdir -p "$REPORTS_DIR"

echo "=== Generating Software Bill of Materials (SBOM) with Syft ==="
echo "Target: $IMAGE_TARGET"

if ! command -v syft >/dev/null 2>&1; then
    echo "[ERROR] Syft CLI not found in PATH."
    echo "Install Syft: https://github.com/anchore/syft"
    exit 1
fi

echo "[INFO] Generating SPDX SBOM..."
syft "$IMAGE_TARGET" -o spdx-json="$REPORTS_DIR/sbom-spdx.json"

echo "[INFO] Generating CycloneDX SBOM..."
syft "$IMAGE_TARGET" -o cyclonedx-json="$REPORTS_DIR/sbom-cyclonedx.json"

echo "[INFO] Package inventory summary:"
syft "$IMAGE_TARGET" -o table

echo "[OK] SBOM generation complete: $REPORTS_DIR/sbom-spdx.json, $REPORTS_DIR/sbom-cyclonedx.json"
