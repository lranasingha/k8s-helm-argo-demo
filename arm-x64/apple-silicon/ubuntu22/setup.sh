#!/bin/bash

# Exit on any error
set -e

# Disable password prompts during installation
export DEBIAN_FRONTEND=noninteractive

# Define versions
HELM_VERSION="v3.12.0"
ARGOCD_VERSION="v2.8.1"
NGINX_HELM_CHART_VERSION="18.2.2"
K3S_VERSION="v1.27.4+k3s1"

# Ensure non-root user
if [ "$EUID" -eq 0 ]; then
  echo "Please run this script as a non-root user."
  exit 1
fi

# Install Docker rootless mode
install_docker_rootless() {
  if ! command -v docker &> /dev/null; then
    echo "Installing Docker rootless mode..."
    curl -fsSL https://get.docker.com/rootless | sh
    export PATH=$HOME/bin:$PATH
    export DOCKER_HOST=unix:///run/user/$UID/docker.sock
    systemctl --user start docker
    loginctl enable-linger $USER
    echo "Docker rootless installed successfully."
  else
    echo "Docker rootless is already installed."
  fi
  docker --version
}

# Install k3s (lightweight Kubernetes)
install_k3s() {
  if ! command -v k3s &> /dev/null; then
    echo "Installing K3s (lightweight Kubernetes)..."
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
    mkdir -p ~/.kube
    cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    chmod 600 ~/.kube/config
  else
    echo "K3s is already installed."
  fi
  export KUBECONFIG=~/.kube/config
  kubectl get nodes
}

# Install Helm
install_helm() {
  if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    wget https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz
    tar -zxvf helm-${HELM_VERSION}-linux-arm64.tar.gz
    sudo mv linux-arm64/helm /usr/local/bin/helm
    rm -rf linux-arm64 helm-${HELM_VERSION}-linux-arm64.tar.gz
  else
    echo "Helm is already installed."
  fi
  helm version
}

# Check if all pods are running before proceeding to ArgoCD installation
wait_for_all_pods() {
  echo "Checking the status of all pods in the cluster..."
  # Timeout after 5 minutes (300 seconds)
  TIMEOUT=300
  INTERVAL=10
  ELAPSED=0

  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    # Check if all pods are running
    if kubectl get pods --all-namespaces | grep -v Running | grep -v Completed; then
      echo "Some pods are still not ready, waiting..."
      sleep $INTERVAL
      ((ELAPSED+=INTERVAL))
    else
      echo "All pods are running! Proceeding to ArgoCD setup."
      return
    fi
  done

  echo "Error: Pods did not reach the 'Running' state within the timeout period."
  exit 1
}

# Install ArgoCD only after all pods are successfully started
install_argocd() {
  wait_for_all_pods  # Ensure all pods are running before ArgoCD setup

  kubectl create namespace argocd || true
  echo "Installing ArgoCD..."
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  # Wait for ArgoCD to pull its images and be ready
  kubectl rollout status deployment argocd-server -n argocd --timeout=600s || {
    echo "Error: ArgoCD server failed to start."
    exit 1
  }
  kubectl rollout status deployment argocd-repo-server -n argocd --timeout=600s || {
    echo "Error: ArgoCD repo server failed to start."
    exit 1
  }
}

# Deploy NGINX via ArgoCD (Create ArgoCD Application)
deploy_nginx_via_argocd() {
  echo "Creating NGINX namespace..."
  kubectl create namespace nginx || true

  echo "Creating ArgoCD application for NGINX..."

  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
spec:
  destination:
    namespace: nginx
    server: https://kubernetes.default.svc
  project: default
  source:
    helm:
      valueFiles: []
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: ${NGINX_HELM_CHART_VERSION}
    helm:
      parameters:
      - name: service.type
        value: NodePort
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

  echo "Waiting for NGINX deployment to be created by ArgoCD..."

  # Poll for the deployment until it becomes available
  TIMEOUT=600  # 10 minutes
  INTERVAL=10
  ELAPSED=0

  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if kubectl get deployment nginx -n nginx; then
      echo "NGINX deployment found. Proceeding to wait for rollout."
      kubectl rollout status deployment nginx-app -n nginx --timeout=600s || {
        echo "Error: NGINX deployment rollout failed."
        exit 1
      }
      return
    else
      echo "NGINX deployment not yet created, waiting..."
      sleep $INTERVAL
      ((ELAPSED+=INTERVAL))
    fi
  done

  echo "Error: NGINX deployment was not created within the timeout period."
  exit 1
}

# Expose ArgoCD and Nginx via NodePort
expose_services() {
  echo "Exposing ArgoCD and Nginx services..."
  kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
  ARGOCD_PORT=$(kubectl -n argocd get svc argocd-server -o=jsonpath='{.spec.ports[0].nodePort}')

  kubectl patch svc nginx-app -n nginx -p '{"spec": {"type": "NodePort"}}'
  NGINX_PORT=$(kubectl -n nginx get svc nginx-app -o=jsonpath='{.spec.ports[0].nodePort}')

  ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)

  echo "========================================================"
  echo "ArgoCD server is accessible at http://<VM-IP>:$ARGOCD_PORT"
  echo "ArgoCD Admin Username: admin"
  echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"
  echo "Nginx service is accessible at http://<VM-IP>:$NGINX_PORT"
  echo "========================================================"
}

# Install all components
install_docker_rootless
install_k3s
install_helm
install_argocd
deploy_nginx_via_argocd
expose_services