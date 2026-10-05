# Cloud-Native DevSecOps Platform: Runtime Security, eBPF & Zero Trust

[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s-326CE5?logo=kubernetes&logoColor=white)](https://k3s.io/)
[![eBPF](https://img.shields.io/badge/eBPF-Cilium%20Tetragon-orange?logo=linux&logoColor=white)](https://tetragon.io/)
[![Kyverno](https://img.shields.io/badge/Policy%20Engine-Kyverno-blue)](https://kyverno.io/)
[![Cosign](https://img.shields.io/badge/Supply%20Chain-Cosign-red)](https://github.com/sigstore/cosign)
[![Trivy](https://img.shields.io/badge/Vulnerability%20Scan-Trivy-00A871)](https://trivy.dev/)
[![Monitoring](https://img.shields.io/badge/Observability-Prometheus%20%26%20Grafana-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Security](https://img.shields.io/badge/Architecture-Zero%20Trust-success)](#)

---

## 📌 Executive Summary

Production-grade **Cloud-Native DevSecOps Platform** designed to enforce **Defense-in-Depth** and **Zero Trust** security across the entire container lifecycle:

1. **Software Supply Chain Security (CI/CD)**: Vulnerability scanning (Trivy), SBOM generation (Syft, SPDX/CycloneDX), and cryptographic container signing & attestation (Cosign).
2. **Admission Control & Zero Trust Policies (Kyverno)**: Declarative admission webhooks blocking non-compliant pods (`runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities) and rejecting unsigned images.
3. **Low-Level Runtime Security & Kernel Surveillance (Cilium Tetragon eBPF)**: Real-time kernel monitoring detecting privilege escalations (`commit_creds`), sensitive file access (`/etc/shadow`), and intercepting malicious tools with automated `SIGKILL`.
4. **Dynamic Network Security & Automated Quarantine**: Zero-Trust network policies with an event-driven controller that isolates compromised pods into an instant 100% blackhole.
5. **Unified Observability & Alerting (Prometheus & Grafana)**: Real-time telemetry, high-severity alerting rules, and an executive SOC dashboard.

---

## 🏛️ Architecture Overview

```text
                                  ┌───────────────────────────────────────┐
                                  │      CI / Supply Chain Pipeline       │
                                  │  (Trivy Scan -> Syft SBOM -> Cosign)  │
                                  └───────────────────┬───────────────────┘
                                                      │ Signed Image & SBOM
                                                      ▼
                                  ┌───────────────────────────────────────┐
                                  │    Kyverno Admission Controller       │
                                  │    • Verify Cosign Signatures         │
                                  │    • Zero Trust (Non-Root, RO fs)     │
                                  └───────────────────┬───────────────────┘
                                                      │ Admitted Pod
                                                      ▼
  ┌───────────────────────────────────────────────────────────────────────────────────┐
  │ Kubernetes Cluster                                                                │
  │                                                                                   │
  │  ┌───────────────────────────┐             ┌──────────────────────────────────┐   │
  │  │ Application Pod           │             │ DaemonSet Cilium Tetragon (eBPF) │   │
  │  │ Namespace: secured-apps   │             │ Real-time Kernel Surveillance:   │   │
  │  │ • UID > 1000 (Non-root)   │             │ • commit_creds (PrivEsc)         │   │
  │  │ • ReadOnlyRootFilesystem  │             │ • sys_enter_execve (nmap, nc...) │   │
  │  │ • Drop ALL capabilities   │             │ • security_file_open (/etc/shadow│   │
  │  └─────────────┬─────────────┘             └─────────────────┬────────────────┘   │
  │                │                                             │                    │
  │                │                                             │ Threat Event       │
  │                ▼                                             ▼ (SIGKILL + Event)  │
  │  ┌───────────────────────────┐             ┌─────────────────┬────────────────┐   │
  │  │ Dynamic Network Quarantine│ <────────── │ Quarantine Controller (Python)   │   │
  │  │ (100% Ingress/Egress Drop)│  Label Pod  │ • Listens to Tetragon events     │   │
  │  └───────────────────────────┘             │ • Applies 'quarantined' label    │   │
  └───────────────────────────────────────────────────────────────────────────────────┘
                               │                                 │
                               ▼                                 ▼
  ┌───────────────────────────────────────────────────────────────────────────────────┐
  │ Observability & Alerting (Prometheus & Grafana)                                   │
  │ • Scrapes Tetragon eBPF (:2112) and Kyverno metrics (:8000)                       │
  │ • Critical alert rules (SIGKILL, admission violations, quarantined pods)          │
  │ • Executive SOC Dashboard in Grafana                                              │
  └───────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Repository Structure

```text
├── Makefile                                  # Standard automation targets (build, deploy, test)
├── cluster/                                  # Cluster bootstrap & hardened k3s config
│   ├── install-k3s.sh                        # Hardened k3s installer with eBPF mount checks
│   └── k3s-config.yaml                       # Hardened k3s server configuration
├── ebpf-tetragon/                            # Runtime kernel surveillance via eBPF
│   ├── values-tetragon.yaml                  # Helm values with Prometheus export enabled
│   └── policies/                             # eBPF TracingPolicy CRDs
│       ├── 01-detect-privilege-escalation.yaml  # Intercepts commit_creds & setuid
│       ├── 02-sensitive-file-access.yaml        # Intercepts /etc/shadow, tokens
│       ├── 03-suspicious-binary-exec.yaml       # Intercepts nmap, netcat with SIGKILL
│       └── 04-namespace-breakout.yaml           # Intercepts setns & unshare
├── kyverno/                                  # Zero-Trust Admission Controller
│   ├── values-kyverno.yaml                   # Helm configuration for Kyverno
│   └── policies/                             # Declarative ClusterPolicies (Enforce)
│       ├── 01-disallow-root-user.yaml           # Enforces runAsNonRoot: true
│       ├── 02-readonly-root-filesystem.yaml     # Enforces readOnlyRootFilesystem: true
│       ├── 03-drop-all-capabilities.yaml        # Drops ALL Linux capabilities
│       ├── 04-disallow-privilege-escalation.yaml# Enforces allowPrivilegeEscalation: false
│       ├── 05-block-latest-tag.yaml             # Rejects untagged & :latest images
│       └── 06-verify-image-cosign.yaml          # Cryptographic signature verification
├── supply-chain/                             # Software Supply Chain Security
│   ├── Dockerfile.demo                       # Multi-stage distroless hardened container
│   ├── generate-keys.sh                      # Cosign ECDSA keypair generation
│   ├── scan-trivy.sh                         # Static vulnerability & IaC scanner
│   ├── generate-sbom.sh                      # SPDX and CycloneDX SBOM generator (Syft)
│   ├── sign-image.sh                         # Container image signing & SBOM attestation
│   └── ci-pipeline.yaml                      # Unified GitHub Actions / GitLab CI pipeline
├── network-security/                         # Network security & dynamic isolation
│   ├── default-deny-all.yaml                 # Baseline Zero-Trust NetworkPolicy
│   ├── allow-dns-and-monitoring.yaml         # Whitelisted DNS & scraping egress
│   └── auto-quarantine/                      # Automated response controller
│       ├── quarantine-controller.py          # Real-time event listener & auto-labeler
│       ├── quarantine-deployment.yaml        # In-cluster deployment & RBAC
│       └── quarantine-networkpolicy.yaml     # Total isolation policy (Blackhole)
├── monitoring/                               # Observability & Alerting
│   ├── prometheus/
│   │   ├── values-prometheus.yaml            # Prometheus stack configuration
│   │   └── alerts-devsecops.yaml             # Critical PrometheusRule definitions
│   └── grafana/
│       └── dashboards/
│           └── devsecops-dashboard.json      # Executive SOC Grafana dashboard
├── scenarios/                                # Offensive & defensive validation scenarios
│   ├── 01-test-tetragon-detection.sh         # Test eBPF kernel intercept & SIGKILL
│   ├── 02-test-kyverno-prevention.sh         # Test admission policy rejection
│   ├── 03-test-supply-chain-verification.sh  # Test Cosign unsigned image rejection
│   └── 04-test-network-quarantine.sh         # Test dynamic network isolation
├── docs/                                     # Technical documentation
│   └── architecture-technique.md             # In-depth architectural specification
└── scripts/
    ├── bootstrap.sh                          # Automated one-click deployment
    └── status.sh                             # Full-stack diagnostic and audit script
```

---

## 🚀 Quick Start Guide

### 1. Prerequisites
- Linux machine or WSL2 (kernel 5.15+ with eBPF support enabled)
- `kubectl`, `helm` (v3+), `make`

### 2. Automated Bootstrap
Clone and deploy the platform:
```bash
git clone https://github.com/hamzahanich/devsecops-cloudnative-platform.git
cd devsecops-cloudnative-platform
make all
```

### 3. Check Platform Health
```bash
make status
```

### 4. Run Demonstration Scenarios (Red Team vs Blue Team)
```bash
make test
```

Individual test executions:
```bash
# Scenario 1: eBPF Runtime Interception (Tetragon enforces SIGKILL on offensive tools)
./scenarios/01-test-tetragon-detection.sh

# Scenario 2: Zero-Trust Admission Rejection (Kyverno blocks root user and writable fs)
./scenarios/02-test-kyverno-prevention.sh

# Scenario 3: Supply Chain Validation (Kyverno rejects unsigned container image)
./scenarios/03-test-supply-chain-verification.sh

# Scenario 4: Automated Network Quarantine (Dynamic isolation of compromised pod)
./scenarios/04-test-network-quarantine.sh
```

### 5. Access Observability (Grafana)
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin / admin)
```

---

## 🛡️ Active Security Policy Matrix

| Layer | Policy / Rule | Technical Mechanism | Response Action | Mode |
| :--- | :--- | :--- | :--- | :---: |
| **eBPF Tetragon** | `detect-privilege-escalation` | Kprobe `commit_creds` & `sys_setuid` | **Instant SIGKILL** | `Enforce` |
| **eBPF Tetragon** | `detect-suspicious-binary-exec` | Syscall `sys_enter_execve` (nmap, nc) | **Instant SIGKILL** | `Enforce` |
| **eBPF Tetragon** | `detect-sensitive-file-access` | LSM Hook `security_file_open` (/etc/shadow) | **Audit & Alerting** | `Enforce` |
| **Kyverno** | `disallow-root-user` | Admission Webhook (`runAsNonRoot: true`) | **Admission Blocked** | `Enforce` |
| **Kyverno** | `readonly-root-filesystem` | Admission Webhook (`readOnlyRootFilesystem`) | **Admission Blocked** | `Enforce` |
| **Kyverno** | `verify-image-signature` | Cryptographic Cosign Verification (ECDSA) | **Admission Blocked** | `Enforce` |
| **NetworkPolicy** | `dynamic-quarantine-isolate` | Label Selector `security-status=quarantined` | **100% Ingress/Egress Drop** | `Active` |
| **Supply Chain** | `trivy-scan-gate` | CI/CD Gate on HIGH/CRITICAL CVEs | **Fail CI Pipeline** | `Active` |

---

## 📜 License
This project is licensed under the [MIT License](LICENSE).
