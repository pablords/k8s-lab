#!/bin/bash
set -e

echo "🚀 Implantando OpenSearch..."

# Criar namespace apenas se não existir
if kubectl get namespace observability >/dev/null 2>&1; then
  echo "✅ Namespace 'observability' já existe. Usando o existente."
else
  echo "🔹 Criando namespace 'observability'..."
  kubectl create namespace observability
fi

# Aplicar manifestos do OpenSearch
kubectl apply -f k8s/observability/opensearch.yml

# Aguardar OpenSearch iniciar
echo "⏳ Aguardando OpenSearch ficar pronto..."
kubectl rollout status statefulset/opensearch -n observability

# Aplicar Jaeger (Tracing)
echo "🚀 Instalando Jaeger (Collector & Query)..."
kubectl apply -f k8s/observability/jaeger.yml

# Aguardar Jaeger
echo "⏳ Aguardando Jaeger ficar pronto..."
kubectl rollout status deployment/jaeger-collector -n observability
kubectl rollout status deployment/jaeger-query -n observability

# Aplicar Collector e Instrumentation
echo "🚀 Configurando OpenTelemetry..."
kubectl apply -f k8s/observability/open-telemetry.yml
kubectl apply -f k8s/observability/instrumentation.yml

echo "✅ OpenSearch e Jaeger (Tracing) prontos!"
