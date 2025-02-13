#!/bin/bash

set -e  # Para encerrar em caso de erro

NODES=2
CPUS=4
MEMORY=10000
DISK=10G
DRIVER=docker
K8S_VERSION=v1.28.3

echo "🚀 Iniciando configuração do cluster Kubernetes com Minikube..."
echo "nodes: $NODES, cpus: $CPUS, memory: $MEMORY, disk: $DISK, driver: $DRIVER, k8s_version: $K8S_VERSION"

# 1️⃣ Iniciar o Minikube com 4 nós, CPUs e memória configuradas
echo "🔥 Iniciando Minikube..."
minikube start --nodes=$NODES --cpus=$CPUS --memory=$MEMORY --disk-size=$DISK --driver=$DRIVER --kubernetes-version=$K8S_VERSION

# 2️⃣ Habilitar o MetalLB
echo "✅ Habilitando MetalLB..."
minikube addons enable metallb

# 3️⃣ Configurar o intervalo de IPs do MetalLB
echo "🔍 Obtendo IP do Minikube..."
MINIKUBE_IP=$(minikube ip)
SUBNET=$(echo $MINIKUBE_IP | awk -F '.' '{print $1"."$2"."$3".0/24"}')

echo "🌐 Definindo intervalo de IPs para MetalLB..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: config
  namespace: metallb-system
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${MINIKUBE_IP%.*}.200-${MINIKUBE_IP%.*}.210
EOF

# 4️⃣ Iniciar Dashboard (opcional)
echo "📊 Iniciando Minikube Dashboard..."
minikube dashboard &

# 5️⃣ Instalar Istio
echo "🛠 Instalando Istio..."
ISTIO_VERSION="1.24.2"
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-$ISTIO_VERSION/bin:$PATH
istioctl install --set profile=demo -y

# 6️⃣ Verificar se o Ingress Gateway pegou um EXTERNAL-IP
echo "🔍 Verificando EXTERNAL-IP do Istio Ingress Gateway..."
kubectl get svc -n istio-system istio-ingressgateway

# 7️⃣ Criar os namespaces
echo "📂 Criando namespaces..."
kubectl apply -f k8s/config/namespaces.yml

# 8️⃣ Aplicar a configuração do Istio Gateway
echo "🌍 Aplicando configuração do Istio Gateway..."
kubectl apply -f k8s/config/istio/gateway.yml


# 🔹 Instalar Argo CD
echo "🚀 Instalando Argo CD..."
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.basehref": "/argo-cd","server.insecure": "true","server.rootpath": "/argo-cd"}}'
kubectl apply -f k8s/argo-cd/destination-rule.yml
kubectl apply -f k8s/argo-cd/virtual-service.yml


# 🔹 Instalar Argo Rollouts
echo "🚀 Instalando Argo Rollouts..."
kubectl create namespace argo-rollouts
helm install argo-rollouts argo/argo-rollouts --namespace argo-rollouts
kubectl apply -f k8s/argo-rollouts/service.yml
kubectl apply -f k8s/argo-rollouts/virtual-service.yml

# 🔹 Configurar Argo CD para reconhecer Argo Rollouts
echo "🔧 Configurando Argo CD para suportar Argo Rollouts..."
kubectl apply -f k8s/argo-cd/argocd-cm.yml
kubectl rollout restart deployment argocd-server -n argocd

# 9️⃣ Implantar o Nginx com VirtualService e DestinationRule
echo "📦 Implantando apps argocd..."
kubectl apply -f apps/backend/parking/app.yml
kubectl apply -f apps/data/db/app.yml
kubectl apply -f apps/data/messaging/app.yml
kubectl apply -f apps/frontend/nginx/app.yml

EXTERNAL_IP=""
# Aguarda até que o External IP seja atribuído pelo MetalLB
while [ -z "$EXTERNAL_IP" ]; do
  echo "⏳ Aguardando MetalLB atribuir um External IP..."
  sleep 5
  EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)
echo $ARGOCD_PASSWORD > argo_password

echo "🎉 Configuração concluída!"
echo "✅ Aponte $EXTERNAL_IP para lab.com.br em seu arquivo de hosts"
echo "✅ Acesse o nginx para validar ambiente de front em: http://lab.com.br/frontend/nginx"
echo "✅ ArgoCD disponível em: http://lab.com.br/argo-cd utilizando o usuario admin com a senha: $ARGOCD_PASSWORD"


