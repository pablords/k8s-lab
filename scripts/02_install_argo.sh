#!/bin/bash
set -e

echo "🚀 Instalando Argo CD..."
kubectl create namespace argocd || true
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd --namespace argocd

kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure": "true"}}'
kubectl apply -f k8s/argo-cd/destination-rule.yml
kubectl apply -f k8s/argo-cd/virtual-service.yml

kubectl rollout status deployment argocd-server -n argocd

echo "🚀 Instalando Argo Rollouts..."
kubectl create namespace argo-rollouts || true
helm upgrade --install argo-rollouts argo/argo-rollouts --namespace argo-rollouts --set dashboard.enabled=true
kubectl apply -f k8s/argo-rollouts/service.yml
kubectl apply -f k8s/argo-rollouts/virtual-service.yml
kubectl apply -f k8s/argo-cd/argocd-cm.yml
kubectl rollout restart deployment argocd-server -n argocd

kubectl rollout status deployment argo-rollouts-dashboard -n argo-rollouts

echo "✅ Argo CD e Rollouts instalados!"
