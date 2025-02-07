#!/bin/bash

set -e  # Para encerrar em caso de erro

echo "🚀 Iniciando configuração do cluster Kubernetes com Minikube..."

# 1️⃣ Iniciar o Minikube com 4 nós, CPUs e memória configuradas
echo "🔥 Iniciando Minikube..."
minikube start --nodes=4 --cpus=4 --memory=8000 --disk-size=5g --driver=docker --kubernetes-version=v1.28.3

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
ISTIO_VERSION="1.24.2"  # Defina a versão desejada
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

# 9️⃣ Implantar o Nginx com VirtualService e DestinationRule
echo "📦 Implantando Nginx..."
kubectl apply -f k8s/nginx/deployment.yml
kubectl apply -f k8s/nginx/virtual-service.yml
kubectl apply -f k8s/nginx/destination-rule.yml

echo "📦 Implantando Wordpress..."
kubectl apply -f k8s/wordpress/mysql-deployment.yml
kubectl apply -f k8s/wordpress/wordpress-deployment.yml
kubectl apply -f k8s/wordpress/virtual-service.yml
kubectl apply -f k8s/wordpress/destination-rule.yml

EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "🎉 Configuração concluída! Teste o acesso via: http://$EXTERNAL_IP/frontend/nginx"
