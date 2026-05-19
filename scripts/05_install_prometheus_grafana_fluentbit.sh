#!/bin/bash
set -e

echo "🚀 Configurando ConfigMaps de dashboards, provisioning e configs..."

# Criar namespace caso não exista (deve existir pelo script 04)
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# --- Grafana Dashboards ---
echo "🔹 Criando ConfigMap para Grafana Dashboards..."
kubectl delete configmap grafana-dashboards --namespace observability --ignore-not-found
kubectl create configmap grafana-dashboards \
  --namespace observability \
  --from-file=k8s/observability/grafana/dashboards/

# --- Grafana Provisioning (Datasources & Dashboards Provider) ---
echo "🔹 Preparando Datasources do Grafana..."
mkdir -p /tmp/grafana-datasources
cp k8s/observability/grafana/provisioning/datasources/*.yml /tmp/grafana-datasources/

# Atualizando as URLs dos datasources para o K8s
sed -i 's|http://open-search:9200|http://opensearch.observability.svc.cluster.local:9200|g' /tmp/grafana-datasources/opensearch.yml
sed -i 's|http://marketplace-jaeger:16686/jaeger|http://jaeger-query.observability.svc.cluster.local:16686|g' /tmp/grafana-datasources/jaeger.yml
sed -i 's|http://prometheus:9090|http://prometheus.observability.svc.cluster.local:9090|g' /tmp/grafana-datasources/prometheus.yml

kubectl delete configmap grafana-datasources --namespace observability --ignore-not-found
kubectl create configmap grafana-datasources \
  --namespace observability \
  --from-file=/tmp/grafana-datasources/

kubectl delete configmap grafana-dashboard-providers --namespace observability --ignore-not-found
kubectl create configmap grafana-dashboard-providers \
  --namespace observability \
  --from-file=k8s/observability/grafana/provisioning/dashboards/

# --- Fluent-Bit Config ---
echo "🔹 Preparando configs do Fluent-Bit..."
kubectl delete configmap fluent-bit-config --namespace observability --ignore-not-found
kubectl create configmap fluent-bit-config \
  --namespace observability \
  --from-file=k8s/observability/fluent-bit/


# --- Prometheus Config ---
echo "🔹 Preparando config do Prometheus..."
kubectl delete configmap prometheus-config --namespace observability --ignore-not-found
kubectl create configmap prometheus-config \
  --namespace observability \
  --from-file=k8s/observability/prometheus/



# --- Aplicar os Manifestos do Kubernetes ---
echo "🚀 Implantando Prometheus..."
kubectl apply -f k8s/observability/prometheus.yml

echo "🚀 Implantando Grafana..."
kubectl apply -f k8s/observability/grafana.yml

echo "🚀 Implantando Fluent-Bit..."
kubectl apply -f k8s/observability/fluent-bit.yml

echo "✅ Monitoramento Nativo configurado!"
