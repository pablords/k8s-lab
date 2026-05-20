#!/bin/bash
set -e

NODES=3
CPUS=6
MEMORY=24000
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

echo "📦 Carregando imagens locais do Marketplace no Minikube..."
IMAGES=(
  "marketplace/api-gateway:latest"
  "marketplace/catalog-service:latest"
  "marketplace/indexing-service:latest"
  "marketplace/search-service:latest"
  "marketplace/ml-ranking-service:latest"
  "marketplace/ml-embedding-service:latest"
)

for img in "${IMAGES[@]}"; do
  echo "🔹 Carregando $img..."
  svc_name="${img#marketplace/}"
  
  # 1. Tenta carregar diretamente via minikube
  if ! minikube image load "$img" --overwrite=true; then
    echo "⚠️ Falha no carregamento direto de $img. Usando fallback via tarball..."
    tmp_tar="/tmp/${img//\//_}.tar"
    
    # 2. Tenta fazer o docker save com timeout de 30 segundos
    if ! timeout 30s docker save -o "$tmp_tar" "$img"; then
      echo "❌ Imagem local de $img está corrompida ou incompleta (blobs ausentes)."
      echo "🔄 Tentando restaurar a imagem fazendo pull da versão oficial 'pablords/$svc_name'..."
      
      # 3. Pull da imagem oficial para curar a imagem local
      docker pull "pablords/$svc_name"
      docker tag "pablords/$svc_name" "$img"
      
      # 4. Refaz o export da imagem restaurada
      echo "🔄 Refazendo o export da imagem restaurada..."
      docker save -o "$tmp_tar" "$img"
    fi
    
    # 5. Carrega o tarball no Minikube e remove o arquivo temporário
    minikube image load "$tmp_tar" --overwrite=true
    rm -f "$tmp_tar"
  fi
  echo "✅ Imagem $img carregada com sucesso!"
done

echo "✅ Cluster preparado!"

