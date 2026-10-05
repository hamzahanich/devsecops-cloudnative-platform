# Architecture Technique Détaillée : Plateforme DevSecOps Cloud-Native

## 1. Introduction & Objectifs Stratégiques

Cette plateforme répond aux exigences strictes de la sécurité moderne en environnement Cloud-Native (Kubernetes) selon le modèle **Zero-Trust** et le principe de **Défense en Profondeur** (*Defense in Depth*) :
1. **Sécurité Déclarative (Shift-Left)** : Aucun artefact non conforme ou vulnérable ne pénètre le cluster.
2. **Contrôle d'Admission Strict (Gatekeeping)** : Interdiction systématique des configurations à risque (UID 0, systèmes de fichiers inscriptibles, privilèges superflus).
3. **Surveillance Runtime Bas Niveau (eBPF)** : Détection et blocage chirurgical dans le noyau Linux des comportements anormaux et élévations de privilèges en temps réel.
4. **Réaction et Confinement Réseau Dynamique** : Isolation instantanée d'un pod dès l'identification d'une intrusion.
5. **Observabilité Unifiée** : Centralisation des métriques, alertes et tableaux de bord de sécurité pour les équipes SOC/SecOps.

---

## 2. Décomposition des Composants Techniques

```
                                  +---------------------------------------+
                                  |      Pipeline CI / Supply Chain       |
                                  |  (Trivy Scan -> Syft SBOM -> Cosign)  |
                                  +-------------------+-------------------+
                                                      | Image signée & SBOM
                                                      v
                                  +---------------------------------------+
                                  |    Kyverno Admission Controller       |
                                  |    - Vérification Signature Cosign    |
                                  |    - Zero Trust (Non-Root, RO fs)     |
                                  +-------------------+-------------------+
                                                      | Validation d'admission
                                                      v
  +-----------------------------------------------------------------------------------+
  | Kubernetes Cluster (k3s)                                                          |
  |                                                                                   |
  |  +---------------------------+             +----------------------------------+   |
  |  | Pod Applicatif            |             | DaemonSet Cilium Tetragon (eBPF) |   |
  |  | Namespace: secured-apps   |             | Surveillance Noyau Linux :       |   |
  |  | - UID > 1000              |             | - commit_creds (PrivEsc)         |   |
  |  | - ReadOnlyRootFilesystem  |             | - sys_enter_execve (nmap, nc...) |   |
  |  | - Drop ALL capabilities   |             | - security_file_open (/etc/shadow|   |
  |  +-------------+-------------+             +-----------------+----------------+   |
  |                |                                             |                    |
  |                |                                             | Détection menace   |
  |                v                                             v (SIGKILL + Event)  |
  |  +---------------------------+             +-----------------+----------------+   |
  |  | NetworkPolicy Quarantaine | <---------- | Quarantine Controller (Python)   |   |
  |  | (Blackhole Ingress/Egress)|  Label Pod  | - Écoute logs Tetragon           |   |
  |  +---------------------------+             | - Applique label 'quarantined'   |   |
  +-----------------------------------------------------------------------------------+
                               |                                 |
                               v                                 v
  +-----------------------------------------------------------------------------------+
  | Stack Observabilité & Alerting (Prometheus & Grafana)                             |
  | - Scrapes métriques Tetragon (2112) et Kyverno (8000)                             |
  | - Alertes critiques (SIGKILL, violation admission, pod quarantiné)               |
  | - Dashboard Executive SOC DevSecOps                                               |
  +-----------------------------------------------------------------------------------+
```

---

## 3. Détail des Modules

### 3.1. Surveillance Bas Niveau & Détection par eBPF (Cilium Tetragon)
Contrairement aux agents en espace utilisateur (userspace) facilement contournables ou coûteux en CPU, **Tetragon** injecte des programmes eBPF directement dans les points d'accroche du noyau Linux :
- **Tracepoints & Kprobes** : Surveillance des appels système `sys_enter_execve` pour interdire l'exécution d'outils de reconnaissance ou de pivoting (`nmap`, `netcat`, `socat`).
- **LSM Hooks & Kprobes sur les structures d'autorisations** :
  - `commit_creds` : Intercepte les exploits modifiant les privilèges de processus en mémoire vers l'UID 0 (Root).
  - `security_file_open` : Traçage des accès non autorisés aux fichiers sensibles (`/etc/shadow`, `/etc/sudoers`, `/root/.ssh`, tokens SA K8s).
- **Enforcement en Noyau** : Capacité unique d'émettre un signal `SIGKILL` directement dans le contexte d'exécution du noyau avant même que l'appel système ne termine son exécution.

### 3.2. Durcissement Système & Politiques Zero Trust (Kyverno)
Kyverno agit comme un Webhook d'admission validant et mutant de manière déclarative les manifests Kubernetes :
- **Politique `disallow-root-user`** : Interdit tout conteneur tentant de s'exécuter avec l'UID 0 ou sans `runAsNonRoot: true`.
- **Politique `readonly-root-filesystem`** : Neutralise les attaques déposant des binaires malveillants ou scripts dans `/tmp` ou `/bin`.
- **Politique `drop-all-capabilities`** : Supprime l'ensemble des capacités Linux Linux (`CAP_SYS_ADMIN`, `CAP_NET_RAW`...).
- **Politique `disallow-privilege-escalation`** : Active le flag noyau `no_new_privs`.
- **Politique `block-latest-tag`** : Force l'immutabilité et le versionnage strict des images.
- **Politique `verify-image-cosign`** : Bloque au niveau de l'API Server toute image de conteneur non signée avec la clé cryptographique officielle.

### 3.3. Sécurité Réseau & Confinement Dynamique (Dynamic Network Isolation)
- **Base Zero-Trust** : Par défaut, tout trafic non explicitement légitimé (Ingress et Egress) est rejeté via une `NetworkPolicy` globale (`default-deny-all`).
- **Confinement Dynamique (Auto-Quarantine)** :
  1. Lorsqu'un comportement malveillant est détecté par Tetragon, le contrôleur de quarantaine reçoit l'événement en temps réel.
  2. Le pod ciblé est immédiatement étiqueté avec `security-status=quarantined`.
  3. La `NetworkPolicy` dédiée à la quarantaine sélectionne ce label et ferme instantanément tous les ports Ingress et Egress (isolation totale / blackhole), empêchant l'exfiltration de données et le mouvement latéral.

### 3.4. Supply Chain Security (Trivy, Syft, Cosign)
- **Trivy** : Analyse statique continue des dépendances de code, paquets système et configurations IaC afin de bloquer les vulnérabilités de sévérité HIGH et CRITICAL.
- **Syft** : Génération automatisée des inventaires logiciels complets (SBOM) aux formats standards **SPDX** et **CycloneDX**.
- **Cosign** : Signature asymétrique ECDSA P-256 de l'image de conteneur et attestation cryptographique du SBOM (in-toto predicate).

### 3.5. Observabilité & Alerting (Prometheus & Grafana)
- Métriques eBPF exposées nativement par Tetragon (`tetragon_policy_filter_actions_total`, `tetragon_events_total`).
- Métriques d'admission exposées par Kyverno (`kyverno_admission_requests_total`).
- Règles d'alertes Prometheus générant des notifications d'incidents critiques.
- Dashboard Grafana interactif pour le suivi en temps réel de la posture de sécurité.
