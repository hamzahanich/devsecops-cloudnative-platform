# ==============================================================================
# Makefile - DevSecOps Cloud-Native Platform
# ==============================================================================

SHELL := /bin/bash

.PHONY: all help cluster tetragon kyverno network supply-chain monitoring test clean status

all: cluster tetragon kyverno network monitoring

help:
	@echo "DevSecOps Cloud-Native Platform - Make targets:"
	@echo "  make cluster        - Install and harden local k3s cluster with eBPF support"
	@echo "  make tetragon       - Deploy Cilium Tetragon and eBPF TracingPolicies"
	@echo "  make kyverno        - Deploy Kyverno admission controller and Zero-Trust policies"
	@echo "  make network        - Apply Zero-Trust NetworkPolicies and quarantine controller"
	@echo "  make supply-chain   - Generate Cosign keys, scan with Trivy, and generate SBOM"
	@echo "  make monitoring     - Deploy Prometheus stack, alerts, and Grafana dashboard"
	@echo "  make status         - Run full-stack platform health audit"
	@echo "  make test           - Run all 4 red-team / blue-team validation scenarios"
	@echo "  make clean          - Remove test resources and temporary namespaces"

cluster:
	@chmod +x cluster/install-k3s.sh
	@./cluster/install-k3s.sh

tetragon:
	@chmod +x ebpf-tetragon/install-tetragon.sh
	@./ebpf-tetragon/install-tetragon.sh

kyverno:
	@chmod +x kyverno/install-kyverno.sh
	@./kyverno/install-kyverno.sh

network:
	@kubectl create namespace secured-apps --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f network-security/default-deny-all.yaml
	@kubectl apply -f network-security/allow-dns-and-monitoring.yaml
	@kubectl apply -f network-security/auto-quarantine/quarantine-networkpolicy.yaml
	@kubectl create configmap quarantine-controller-script \
		--from-file=network-security/auto-quarantine/quarantine-controller.py \
		-n kube-system --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f network-security/auto-quarantine/quarantine-deployment.yaml

supply-chain:
	@chmod +x supply-chain/*.sh
	@./supply-chain/generate-keys.sh
	@./supply-chain/scan-trivy.sh
	@./supply-chain/generate-sbom.sh

monitoring:
	@chmod +x monitoring/install-monitoring.sh
	@./monitoring/install-monitoring.sh

status:
	@chmod +x scripts/status.sh
	@./scripts/status.sh

test:
	@chmod +x scenarios/*.sh
	@echo "[*] Running Scenario 1: Tetragon eBPF Runtime Interception..."
	@./scenarios/01-test-tetragon-detection.sh
	@echo "[*] Running Scenario 2: Kyverno Zero-Trust Admission..."
	@./scenarios/02-test-kyverno-prevention.sh
	@echo "[*] Running Scenario 3: Supply Chain Signature Verification..."
	@./scenarios/03-test-supply-chain-verification.sh
	@echo "[*] Running Scenario 4: Automated Network Quarantine..."
	@./scenarios/04-test-network-quarantine.sh

clean:
	@kubectl delete namespace test-runtime-security test-zero-trust --ignore-not-found
	@kubectl delete pod compromised-candidate unsigned-image-pod -n secured-apps --ignore-not-found
