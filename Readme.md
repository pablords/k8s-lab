# k8s-labs

### Start

minikube start --nodes=4 --cpus=2 --memory=4048 --disk-size=5g --driver=docker --kubernetes-version=v1.28.3

### Usando MetalLB (Load Balancer Local)
minikube addons list
minikube addons enable metallb

#### configure configmap MetalLB
minikube ip

cd k8s/config/metallb

aplique o configmap no namespace do mteallb-system

Se o Minikube usa 192.168.49.0/24, experimente intervalos como:
192.168.49.200-192.168.49.210
192.168.49.50-192.168.49.60

### Dashboard

minikube dashboard

### Entre no diretório do Istio (o nome varia conforme a versão baixada, ex.: istio-1.18.0):

cd tools/istio-1.24.2
export PATH=$PWD/bin:$PATH

#### Use o comando a seguir para instalar o Istio com a configuração padrão:
istioctl install --set profile=demo -y

Isso instalará:

Control Plane: Os componentes principais do Istio.
Ingress Gateway: Um gateway padrão para gerenciar o tráfego externo.

Valide se o istio-ingressgateway pegou o EXTERNAL-IP

kubectl get svc -n istio-system istio-ingressgateway

#### Crie os namespaces
cd k8s/config
kubectl apply -f namespaces.yml


### Aplique a config do gateway

cd k8/config

kubectl apply -f ingress.yml

#### Aplique os manifestos nginx para teste:
cd k8s/nginx
kubectl apply deployment.yml
kubectl apply virtual-service.yml
kubectl apply destination-rule.yml

#### Use o dashboard do Istio para monitorar o tráfego:
istioctl dashboard kiali


### Ferramentas de monitoramento adicionais: Instale ferramentas como Prometheus e Grafana usando Helm:

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

Essa instalação inclui:

Prometheus: Coleta métricas do cluster.
Grafana: Exibe as métricas em dashboards pré-configurados.
Alertmanager: Gerencia alertas.
Node Exporter: Coleta métricas dos nós do cluster.

Passo 1: Obtenha o IP Externo ou Porta do Grafana
Verifique os serviços instalados:

bash
kubectl get svc -n monitoring


3️⃣ Testar o acesso ao WordPress:

curl -v http://$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/wordpress/wp-admin/install.php


Tshoot istio

kubectl get virtualservice -A
kubectl get svc -A
istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system
kubectl logs -l istio=ingressgateway -n istio-system --tail=100
kubectl rollout restart deployment istio-ingressgateway -n istio-system
kubectl rollout restart deployment parking -n backend

export PATH=$PWD/bin:$PATH


curl -X POST http://localhost:8080/api/checkins \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "plate": "HPP7156",
  "brand": "LAMBORGHINI",
  "color": "azul",
  "model": "Gallardo Spider LP560-4"
}'


kubectl exec -it parking-7bbd74c997-lcscw -n backend -- curl -X POST http://parking.backend.svc.cluster.local:8080/api/checkins \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "plate": "HPP7156",
  "brand": "LAMBORGHINI",
  "color": "azul",
  "model": "Gallardo Spider LP560-4"
}'


curl -X POST http://lab.com.br/backend/parking/api/checkins \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "plate": "HPP7156",
  "brand": "LAMBORGHINI",
  "color": "azul",
  "model": "Gallardo Spider LP560-4"
}'