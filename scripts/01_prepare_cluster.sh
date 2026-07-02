#!/bin/bash
set -e

NODES=3
CPUS=6
MEMORY=24000
DISK=30G
DRIVER=docker
K8S_VERSION=v1.28.3
IP=$(hostname -I | awk '{print $1}')

echo "🚀 Iniciando Minikube com suporte a Registro Inseguro (host.minikube.internal:5001, registry:5000)..."
minikube start --mount --nodes=$NODES --cpus=$CPUS --memory=$MEMORY --disk-size=$DISK --driver=$DRIVER --kubernetes-version=$K8S_VERSION --apiserver-ips=$IP --insecure-registry="host.minikube.internal:5001,registry:5000" 

echo "✅ Habilitando MetalLB..."
minikube addons enable metallb
minikube addons enable metrics-server

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
  echo "📊 Iniciando Minikube Dashboard em background..."
  minikube dashboard &
else
  echo "✅ Minikube Dashboard já está rodando em segundo plano."
fi

# ─────────────────────────────────────────────────────────────────
# Iniciar o registry local (se não existir)
# ─────────────────────────────────────────────────────────────────
echo "📦 Verificando container de registry local..."
if ! docker container inspect registry >/dev/null 2>&1; then
  echo "   🔹 Criando container registry na porta 5001..."
  docker run -d -p 5001:5000 --restart=always --name registry registry:2
else
  if [ "$(docker inspect -f '{{.State.Running}}' registry)" != "true" ]; then
    echo "   🔹 Iniciando container registry que estava parado..."
    docker start registry
  fi
fi

# ─────────────────────────────────────────────────────────────────
# Conectar o registry local à rede minikube e configurar insecure-
# registry em todos os nós para que possam puxar imagens via IP.
# ─────────────────────────────────────────────────────────────────
echo "🔧 Conectando registry local à rede minikube..."
if ! docker network inspect minikube 2>/dev/null | grep -q '"registry"'; then
  docker network connect minikube registry 2>/dev/null || true
fi

REGISTRY_IP=$(docker inspect registry --format '{{.NetworkSettings.Networks.minikube.IPAddress}}' 2>/dev/null)
if [ -z "$REGISTRY_IP" ]; then
  echo "⚠️  Não foi possível obter o IP do registry na rede minikube. Pulando configuração dos nós."
else
  echo "✅ Registry acessível em $REGISTRY_IP:5000 na rede minikube."
  DOCKER_EXEC_START="/usr/bin/dockerd -H tcp://0.0.0.0:2376 -H unix:///var/run/docker.sock --default-ulimit=nofile=1048576:1048576 --tlsverify --tlscacert /etc/docker/ca.pem --tlscert /etc/docker/server.pem --tlskey /etc/docker/server-key.pem --label provider=docker --insecure-registry 10.96.0.0/12 --insecure-registry host.minikube.internal:5001 --insecure-registry registry:5000 --insecure-registry ${REGISTRY_IP}:5000"

  for node in minikube minikube-m02 minikube-m03; do
    echo "   🔹 Configurando insecure-registry em $node..."
    minikube ssh -n "$node" "
      sudo mkdir -p /etc/systemd/system/docker.service.d
      sudo tee /etc/systemd/system/docker.service.d/insecure-registry.conf > /dev/null << 'DROPIN'
[Service]
ExecStart=
ExecStart=${DOCKER_EXEC_START}
DROPIN
      sudo systemctl daemon-reload
      sudo systemctl reset-failed docker 2>/dev/null || true
      sudo systemctl restart docker
    " && echo "   ✅ Docker reiniciado em $node" || echo "   ⚠️ Erro ao reiniciar Docker em $node"
  done

  echo "⏳ Aguardando cluster se recuperar após restart do Docker..."
  sleep 20
  until kubectl get nodes > /dev/null 2>&1; do
    echo "   ⏳ API server ainda iniciando..."
    sleep 10
  done
  echo "✅ Cluster pronto."
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

echo "📦 Enviando imagens locais para o repositório local (Host Registry)..."
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../marketplace-search-system" && pwd)"
JAVA_COMPILED=false

compile_java_services() {
  if [ "$JAVA_COMPILED" = false ]; then
    echo "☕ Compilando serviços Java com Maven (via Docker + Java 25)..."
    docker run --rm -v "$SRC_DIR":/app -v "$HOME/.m2":/root/.m2 -w /app maven:3.9-eclipse-temurin-21-alpine mvn clean package -DskipTests
    JAVA_COMPILED=true
  fi
}

IMAGES=(
  "pablords/api-gateway:latest"
  "pablords/catalog-service:latest"
  "pablords/indexing-service:latest"
  "pablords/search-service:latest"
  "pablords/ml-ranking-service:latest"
  "pablords/ml-embedding-service:latest"
)

# Sincroniza as tags locais do docker-compose (ranking-service / embedding) com as do k8s (ml-ranking-service / ml-embedding-service)
if docker image inspect marketplace/embedding:latest >/dev/null 2>&1 && ! docker image inspect pablords/ml-embedding-service:latest >/dev/null 2>&1; then
  echo "🔗 Sincronizando tag local de marketplace/embedding para pablords/ml-embedding-service..."
  docker tag marketplace/embedding:latest pablords/ml-embedding-service:latest
fi
if docker image inspect marketplace/ranking-service:latest >/dev/null 2>&1 && ! docker image inspect pablords/ml-ranking-service:latest >/dev/null 2>&1; then
  echo "🔗 Sincronizando tag local de marketplace/ranking-service para pablords/ml-ranking-service..."
  docker tag marketplace/ranking-service:latest pablords/ml-ranking-service:latest
fi

total_imgs=${#IMAGES[@]}
current_idx=0

for img in "${IMAGES[@]}"; do
  current_idx=$((current_idx + 1))
  registry_tag="localhost:5001/$img"
  
  echo "🔹 [$current_idx/$total_imgs] Processando $img..."
  
  # Garante que a imagem local existe (ou constrói localmente)
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    svc_name="${img#pablords/}"
    svc_name="${svc_name%:latest}"
    echo "   ⚠️ Imagem local $img não encontrada. Iniciando build a partir do código fonte..."
    
    case "$svc_name" in
      api-gateway)
        echo "   🛠 Construindo Go api-gateway..."
        docker build -t "$img" "$SRC_DIR/api-gateway"
        ;;
      catalog-service)
        compile_java_services
        echo "   🛠 Construindo Java catalog-service..."
        docker build -t "$img" "$SRC_DIR/catalog-service"
        ;;
      indexing-service)
        compile_java_services
        echo "   🛠 Construindo Java indexing-service..."
        docker build -t "$img" "$SRC_DIR/indexing-service"
        ;;
      search-service)
        compile_java_services
        echo "   🛠 Construindo Java search-service..."
        docker build -t "$img" "$SRC_DIR/search-service"
        ;;
      ml-ranking-service)
        echo "   🛠 Construindo Python ml-ranking-service..."
        docker build -t "$img" "$SRC_DIR/ml-ranking-service"
        ;;
      ml-embedding-service)
        echo "   🛠 Construindo Python ml-embedding-service..."
        docker build -t "$img" "$SRC_DIR/ml-embedding-service"
        ;;
      *)
        echo "   ❌ Serviço desconhecido: $svc_name"
        continue
        ;;
    esac
  fi
  
  # Taggea para o registro local
  echo "   🔗 Taggeando como $registry_tag..."
  docker tag "$img" "$registry_tag"
  
  # Faz o push para o registro local
  echo "   🚀 Enviando para o Host Registry..."
  if docker push "$registry_tag" >/dev/null 2>&1; then
    echo "   ✅ Imagem $img enviada com sucesso para o Host Registry!"
  else
    # Tenta novamente exibindo saída em caso de falha silenciosa
    echo "   ⚠️ Falha silenciosa. Tentando novamente com logs detalhados..."
    if docker push "$registry_tag"; then
      echo "   ✅ Imagem $img enviada com sucesso para o Host Registry!"
    else
      echo "   ❌ Erro ao enviar a imagem $img para o registro local."
    fi
  fi
done

echo "✅ Cluster preparado!"

