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
  --from-file=/k8s-lab/k8s/observability/grafana/provisioning/dashboards/

# --- Grafana Provisioning (Datasources & Dashboards Provider) ---
echo "🔹 Preparando Datasources do Grafana..."
mkdir -p /tmp/grafana-datasources
cp k8s-lab/k8s/observability/grafana/provisioning/datasources/*.yml /tmp/grafana-datasources/

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
  --from-file=/home/pablo/projetos/marketplace-search-system/docker/grafana/provisioning/dashboards/

# --- Fluent-Bit Config ---
echo "🔹 Preparando configs do Fluent-Bit..."
mkdir -p /tmp/fluent-bit-config
cp -r /home/pablo/projetos/marketplace-search-system/docker/fluent-bit/* /tmp/fluent-bit-config/

# Vamos reescrever o fluent-bit.conf para ler dos containers do Kubernetes em vez do modo "forward"
cat << 'EOF' > /tmp/fluent-bit-config/fluent-bit.conf
[SERVICE]
    Flush         1
    Log_Level     info
    Daemon        off
    Parsers_File  parsers.conf
    HTTP_Server   On
    HTTP_Listen   0.0.0.0
    HTTP_Port     2020

[INPUT]
    Name              tail
    Tag               kube.*
    Path              /var/log/containers/*.log
    Parser            docker
    DB                /var/log/flb_kube.db
    Mem_Buf_Limit     5MB
    Skip_Long_Lines   On
    Refresh_Interval  10

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
    Kube_Tag_Prefix     kube.var.log.containers.
    Merge_Log           On
    Merge_Log_Key       log_processed
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off

[FILTER]
    Name          parser
    Match         kube.*
    Key_Name      log
    Parser        springboot_json
    Parser        springboot
    Reserve_Data  On

[FILTER]
    Name          grep
    Match         *
    Exclude       log actuator/health
    Exclude       log /_cluster/health
    Exclude       message Request received

[FILTER]
    Name          record_modifier
    Match         *
    Record        environment production
    Record        stack marketplace-search-system

[OUTPUT]
    Name                  opensearch
    Match                 *
    Host                  opensearch.observability.svc.cluster.local
    Port                  9200
    Index                 marketplace-logs
    Logstash_Format       On
    Logstash_Prefix       marketplace-logs
    Logstash_DateFormat   %Y.%m.%d
    Buffer_Size           5M
    Generate_ID           On
    Retry_Limit           False
    tls                   Off
    tls.verify            Off
    Suppress_Type_Name    On
EOF

kubectl delete configmap fluent-bit-config --namespace observability --ignore-not-found
kubectl create configmap fluent-bit-config \
  --namespace observability \
  --from-file=/tmp/fluent-bit-config/


# --- Prometheus Config ---
echo "🔹 Preparando config do Prometheus..."
cat << 'EOF' > /tmp/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'marketplace-search-k8s'
    environment: 'development'

scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name
EOF

kubectl delete configmap prometheus-config --namespace observability --ignore-not-found
kubectl create configmap prometheus-config \
  --namespace observability \
  --from-file=prometheus.yml=/tmp/prometheus.yml


# --- Aplicar os Manifestos do Kubernetes ---
echo "🚀 Implantando Prometheus..."
kubectl apply -f k8s/observability/prometheus.yml

echo "🚀 Implantando Grafana..."
kubectl apply -f k8s/observability/grafana.yml

echo "🚀 Implantando Fluent-Bit..."
kubectl apply -f k8s/observability/fluent-bit.yml

echo "✅ Monitoramento Nativo configurado!"
