#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing Hardened k3s Cluster with eBPF Support ==="

# 1. Mount bpf & debug filesystems if missing
if [ ! -d "/sys/kernel/debug" ]; then
    echo "[INFO] Mounting debugfs..."
    sudo mount -t debugfs none /sys/kernel/debug || true
fi

if [ ! -d "/sys/fs/bpf" ]; then
    echo "[INFO] Mounting bpffs..."
    sudo mount -t bpf none /sys/fs/bpf || true
fi

# 2. Configure k3s
echo "[INFO] Writing k3s configuration..."
sudo mkdir -p /etc/rancher/k3s
sudo cp "$(dirname "$0")/k3s-config.yaml" /etc/rancher/k3s/config.yaml

export INSTALL_K3S_EXEC="--config /etc/rancher/k3s/config.yaml"

if command -v k3s >/dev/null 2>&1; then
    echo "[INFO] k3s already present, restarting service..."
    sudo systemctl restart k3s || sudo service k3s restart || sudo k3s server &
else
    echo "[INFO] Downloading and installing k3s..."
    curl -sfL https://get.k3s.io | sh -
fi

# 3. Kubeconfig permissions
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

echo "[INFO] Waiting for node to become Ready..."
while ! kubectl get nodes | grep -q " Ready"; do
    sleep 3
done

echo "[OK] k3s cluster is operational."
kubectl get nodes -o wide
