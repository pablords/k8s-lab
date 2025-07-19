#!/bin/bash
set -e

NODES=3
CPUS=6
MEMORY=22000
DISK=30G
DRIVER=docker
K8S_VERSION=v1.28.3
IP=$(hostname -I | awk '{print $1}')

echo "🚀 Iniciando Minikube..."
minikube start --mount --nodes=$NODES --cpus=$CPUS --memory=$MEMORY --disk-size=$DISK --driver=$DRIVER --kubernetes-version=$K8S_VERSION --apiserver-ips=$IP

echo "✅ Habilitando MetalLB..."
minikube addons enable metallb

MINIKUBE_IP=$(minikube ip)
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

echo "📊 Iniciando Minikube Dashboard..."
minikube dashboard &

echo "🛠 Instalando Istio..."
ISTIO_VERSION="1.24.2"
curl -L https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istio-$ISTIO_VERSION-linux-amd64.tar.gz --output istio-$ISTIO_VERSION.tar.gz
tar -xzf istio-$ISTIO_VERSION.tar.gz
export PATH=$PWD/istio-$ISTIO_VERSION/bin:$PATH
istioctl install --set profile=demo -y

kubectl get svc -n istio-system istio-ingressgateway

echo "📂 Criando namespaces..."
kubectl apply -f k8s/config/namespaces.yml

echo "🌍 Aplicando Gateway Istio..."
kubectl apply -f k8s/config/istio/gateway.yml

echo "✅ Cluster preparado!"
