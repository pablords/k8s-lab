#!/bin/bash
set -e

echo "🚀 Implantando Elasticsearch e Kibana..."

# Criar namespace apenas se não existir
if kubectl get namespace observability >/dev/null 2>&1; then
  echo "✅ Namespace 'observability' já existe. Usando o existente."
else
  echo "🔹 Criando namespace 'observability'..."
  kubectl create namespace observability
fi

# Aplicar manifestos
kubectl apply -f k8s/observability/elastic.yml

# Aguardar Elasticsearch iniciar
echo "⏳ Aguardando Elasticsearch ficar pronto..."
kubectl rollout status statefulset/elasticsearch -n observability

# Instalar APM Server
echo "🚀 Instalando APM Server..."
helm repo add elastic https://helm.elastic.co
helm repo update

# Aplicar Collector e Instrumentation
kubectl apply -f k8s/observability/open-telemetry.yml
kubectl apply -f k8s/observability/instrumentation.yml

# Resetar senha kibana_system
echo "🔑 Resetando senha do kibana_system..."

kubectl rollout status statefulset/elasticsearch -n observability

KIBANA_SYSTEM_PASSWORD=$(kubectl exec -n observability statefulset/elasticsearch \
  -- bin/elasticsearch-reset-password -u kibana_system -b 2>/dev/null | grep "New value" | awk '{print $3}' || true)

if [ -z "$KIBANA_SYSTEM_PASSWORD" ]; then
  echo "⚠️ Não foi possível resetar a senha do kibana_system. Verifique o Elasticsearch manualmente."
else
  echo "✅ Senha do kibana_system obtida: $KIBANA_SYSTEM_PASSWORD"
  echo "$KIBANA_SYSTEM_PASSWORD" >kibana_system_password

  kubectl create secret generic kibana-credentials \
    --namespace observability \
    --from-literal=username="kibana_system" \
    --from-literal=password="$KIBANA_SYSTEM_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "🔄 Reiniciando Kibana..."
  kubectl rollout restart deployment kibana -n observability
fi

# Resetar senha elastic
echo "🔑 Resetando senha do elastic..."

ELASTIC_PASSWORD=$(kubectl exec -n observability statefulset/elasticsearch \
  -- bin/elasticsearch-reset-password -u elastic -b 2>/dev/null | grep "New value" | awk '{print $3}' || true)

if [ -z "$ELASTIC_PASSWORD" ]; then
  echo "⚠️ Não foi possível resetar a senha do elastic. Verifique o Elasticsearch manualmente."
else
  echo "✅ Senha do elastic obtida: $ELASTIC_PASSWORD"
  echo "$ELASTIC_PASSWORD" >elastic_password

  kubectl create secret generic elasticsearch-master-credentials \
    --namespace observability \
    --from-literal=username='elastic' \
    --from-literal=password="$ELASTIC_PASSWORD"

  helm upgrade --install apm-server elastic/apm-server \
    --namespace observability \
    -f /tmp/apm-values.yaml

  cat <<EOF >/tmp/apm-values.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: apm-server-apm-server-config
  namespace: observability
data:
  apm-server.yml: |
    apm-server:
      host: "0.0.0.0:8200"

    queue: {}

    output.elasticsearch:
      hosts: ["http://elasticsearch:9200"]
      username: "elastic"
      password: "${ELASTIC_PASSWORD}"
      ## If SSL is enabled
      # protocol: https
      # ssl.certificate_authorities:
      #  - /usr/share/apm-server/config/certs/elastic-ca.pem

EOF

  kubectl apply -f /tmp/apm-values.yaml
  echo "🔄 Reiniciando APM Server..."
  
  kubectl rollout restart deployment apm-server-server -n observability

fi

echo "✅ Elasticsearch, Kibana e APM Server prontos!"

## necessãrio alterar apm-server-apm-server-config manual tirando o master do nome do elastic
