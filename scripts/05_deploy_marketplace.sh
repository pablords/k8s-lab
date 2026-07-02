#!/bin/bash
set -e

echo "⏳ Aguardando pods do cluster (Istio e Observabilidade)..."
kubectl wait --for=condition=Ready pod --all -n istio-system --timeout=300s || true
kubectl wait --for=condition=Ready pod --all -n observability --timeout=300s || true

echo "🚀 Iniciando deploy da infraestrutura base e do Kafka..."
kubectl apply -f apps/kafka/manifest.yml
kubectl apply -f apps/kafka/control-center.yml
kubectl apply -f apps/kafka/schema-registry.yml
kubectl apply -f apps/marketplace/integration/kafka-exporter.yml
kubectl apply -f k8s/observability/opensearch-exporter.yml


echo "🚀 Iniciando deploy do ecossistema Marketplace (aplicando manifestos diretamente)..."
kubectl apply -f apps/marketplace/namespace.yml
find apps/marketplace -name "manifest.yml" -exec kubectl apply -f {} \;

echo "✅ Aplicações submetidas!"

EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  echo "⏳ Aguardando MetalLB atribuir External IP..."
  sleep 5
  EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done

echo "🎉 Tudo pronto!"
echo "✅ Aponte $EXTERNAL_IP para *.lab.com.br no seu /etc/hosts (ex: api.lab.com.br, grafana.lab.com.br)"
echo "✅ API do Marketplace: http://api.lab.com.br/api/"
echo "📊 Para acessar o Dashboard do Kubernetes, execute: make dashboard"
