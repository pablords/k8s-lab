#!/bin/bash
set -e

echo "⏳ Aguardando pods do cluster (Istio e Observabilidade)..."
kubectl wait --for=condition=Ready pod --all -n istio-system --timeout=300s || true
kubectl wait --for=condition=Ready pod --all -n observability --timeout=300s || true

echo "🚀 Iniciando deploy da infraestrutura base e do Kafka..."
kubectl apply -f apps/kafka/manifest.yml

echo "🚀 Iniciando deploy do ecossistema Marketplace via ArgoCD..."
find apps/marketplace -name "app.yml" -exec kubectl apply -f {} \;

echo "✅ Aplicações submetidas! Acompanhe o progresso no painel do ArgoCD."

EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  echo "⏳ Aguardando MetalLB atribuir External IP..."
  sleep 5
  EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)

echo "🎉 Tudo pronto!"
echo "✅ Aponte $EXTERNAL_IP para *.lab.com.br no seu /etc/hosts (ex: api.lab.com.br, argo.lab.com.br)"
echo "✅ ArgoCD: http://argo.lab.com.br/ (admin / senha: $ARGOCD_PASSWORD)"
echo "✅ API do Marketplace: http://api.lab.com.br/api/"
