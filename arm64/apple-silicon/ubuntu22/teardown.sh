#!/bin/bash

# Exit on any error
set -e

# Ensure running as the default Ubuntu user, not root
#if [ "$EUID" -eq 0 ]; then
 # echo "Please run as the default Ubuntu user, not root."
 # exit 1
#fi

# Stop and remove k3s
echo "Stopping and removing k3s..."
if command -v k3s &> /dev/null; then
  sudo /usr/local/bin/k3s-uninstall.sh
  echo "k3s stopped and removed."
else
  echo "k3s not found, skipping."
fi

# Stop Docker rootless services
echo "Stopping Docker rootless..."
if command -v docker &> /dev/null; then
  systemctl --user stop docker
  rm -rf ~/.docker /run/user/$UID/docker.sock
  echo "Docker rootless stopped and files removed."
else
  echo "Docker not found, skipping."
fi

# Delete Helm installations
echo "Deleting Helm installations..."
if command -v helm &> /dev/null; then
  helm uninstall nginx --namespace nginx || true
  rm -rf /usr/local/bin/helm linux-arm64 helm-v3.12.0-linux-arm64.tar.gz
  echo "Helm and Nginx removed."
else
  echo "Helm not found, skipping."
fi

# Delete Kubernetes namespaces and resources
echo "Deleting Kubernetes namespaces and resources..."
kubectl delete namespace argocd nginx || true

# Remove any remaining port forwards
echo "Stopping port forwards..."
pkill -f "kubectl -n argocd port-forward" || true
pkill -f "kubectl -n kube-system port-forward" || true

# Final cleanup
echo "Final cleanup..."
kubectl delete application nginx-app -n argocd || true
rm -rf ~/.kube
sudo rm -f /etc/rancher/k3s/k3s.yaml

echo "Teardown complete. All services stopped and removed."