#!/bin/bash
set -e

echo "⏳ Aguardando pods do cluster..."
kubectl wait --for=condition=Ready pod --all --timeout=300s

echo "🚀 Aplicando apps iniciais..."
kubectl apply -f apps/backend/parking/app.yml
kubectl apply -f apps/data/db/app.yml
kubectl apply -f apps/data/messaging/app.yml
kubectl apply -f apps/frontend/nginx/app.yml
kubectl apply -f apps/kafka/manifest.yml

echo "✅ Aplicações implantadas!"

EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  echo "⏳ Aguardando MetalLB atribuir External IP..."
  sleep 5
  EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)
echo $ARGOCD_PASSWORD > argo_password

echo "🎉 Tudo pronto!"
echo "✅ Aponte $EXTERNAL_IP para lab.com.br no seu /etc/hosts"
echo "✅ ArgoCD: http://lab.com.br/argo-cd (admin / senha: $ARGOCD_PASSWORD)"
echo "✅ Senha elastic: $(cat elastic_password)"
echo "✅ Senha kibana_system: $(cat kibana_system_password)"
