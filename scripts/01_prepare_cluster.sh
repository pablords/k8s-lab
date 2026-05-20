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

echo "⏳ Aguardando namespace metallb-system inicializar..."
until kubectl get namespace metallb-system >/dev/null 2>&1; do
  sleep 1
done

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

if ! pgrep -f "minikube dashboard" > /dev/null; then
  echo "📊 Iniciando Minikube Dashboard..."
  minikube dashboard &
else
  echo "✅ Minikube Dashboard já está rodando em segundo plano."
fi

echo "🛠 Preparando Istio..."
ISTIO_VERSION="1.24.2"

if [ ! -f "istio-$ISTIO_VERSION.tar.gz" ]; then
  echo "📥 Baixando Istio $ISTIO_VERSION..."
  curl -L "https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istio-$ISTIO_VERSION-linux-amd64.tar.gz" --output "istio-$ISTIO_VERSION.tar.gz"
else
  echo "✅ Arquivo istio-$ISTIO_VERSION.tar.gz já existe. Pulando download."
fi

if [ ! -d "istio-$ISTIO_VERSION" ]; then
  echo "📦 Extraindo Istio..."
  tar -xzf "istio-$ISTIO_VERSION.tar.gz"
else
  echo "✅ Diretório istio-$ISTIO_VERSION já existe. Pulando extração."
fi

export PATH=$PWD/istio-$ISTIO_VERSION/bin:$PATH

if kubectl get deployment -n istio-system istiod >/dev/null 2>&1; then
  echo "✅ Istio já está instalado no cluster. Pulando instalação."
else
  echo "🛠 Instalando Istio no cluster..."
  istioctl install --set profile=demo -y
fi

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

# Sincroniza as tags locais do docker-compose (ranking-service / embedding) com as do k8s (ml-ranking-service / ml-embedding-service)
if docker image inspect marketplace/embedding:latest >/dev/null 2>&1; then
  echo "🔗 Sincronizando tag local de marketplace/embedding para marketplace/ml-embedding-service..."
  docker tag marketplace/embedding:latest marketplace/ml-embedding-service:latest
fi
if docker image inspect marketplace/ranking-service:latest >/dev/null 2>&1; then
  echo "🔗 Sincronizando tag local de marketplace/ranking-service para marketplace/ml-ranking-service..."
  docker tag marketplace/ranking-service:latest marketplace/ml-ranking-service:latest
fi

# Obtém a lista de imagens já presentes no Minikube uma única vez para otimizar a busca
LOADED_IMAGES=$(minikube image ls)

for img in "${IMAGES[@]}"; do
  svc_name="${img#marketplace/}"
  img_base="${img%:*}"
  
  # Verifica se a imagem já está no cache do Minikube (mesmo que com prefixo docker.io/)
  if echo "$LOADED_IMAGES" | grep -q "$img_base"; then
    echo "✅ Imagem $img já está presente no Minikube. Pulando..."
    continue
  fi
  
  echo "🔹 Carregando $img..."
  
  # 1. Tenta carregar diretamente via minikube
  if ! minikube image load "$img" --overwrite=true; then
    echo "⚠️ Falha no carregamento direto de $img. Usando fallback via tarball..."
    tmp_tar="/tmp/${img//\//_}.tar"
    
    # 2. Tenta fazer o docker save com timeout de 120 segundos (2 minutos)
    if ! timeout 120s docker save -o "$tmp_tar" "$img"; then
      echo "❌ Imagem local de $img está corrompida ou incompleta."
      
      # 3. Pull da imagem oficial para curar a imagem local se disponível
      echo "🔄 Tentando baixar a versão oficial 'pablords/$svc_name' do Docker Hub..."
      if docker pull "pablords/$svc_name"; then
        docker tag "pablords/$svc_name" "$img"
        echo "🔄 Refazendo o export da imagem restaurada..."
        docker save -o "$tmp_tar" "$img"
      else
        echo "⚠️ Falha ao baixar 'pablords/$svc_name' do Docker Hub. Prosseguindo..."
        rm -f "$tmp_tar"
        continue
      fi
    fi
    
    # 5. Carrega o tarball no Minikube e remove o arquivo temporário
    minikube image load "$tmp_tar" --overwrite=true
    rm -f "$tmp_tar"
  fi
  echo "✅ Imagem $img carregada com sucesso!"
done

echo "✅ Cluster preparado!"

