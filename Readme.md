# k8s-lab - Cluster Kubernetes com Minikube, MetalLB, Istio, Argo CD e Argo Rollouts

Este repositório contém um script automatizado para configurar um cluster Kubernetes local utilizando Minikube, MetalLB, Istio, Argo CD e Argo Rollouts.

## 🚀 Funcionalidades

- **Criação de cluster Kubernetes** com Minikube
- **Habilitação do MetalLB** para Load Balancer
- **Instalação do Istio** e configuração do Gateway
- **Implantação de serviços essenciais** como banco de dados e mensageria
- **Configuração do Argo CD** para gerenciamento de aplicações com GitOps
- **Instalação do Argo Rollouts** para deploys progressivos e Canary Deploy
- **Geração automática do IP externo do ambiente**

---

## 🔥 Iniciando a Configuração

### **1️⃣ Executar o Script**
Execute o script para iniciar a configuração completa do ambiente:
```bash
chmod +x setup.sh
./setup.sh
```

O script fará todas as configurações automaticamente.

---

## 🛠 O que o Script Faz?

### **1️⃣ Iniciar o Cluster Kubernetes com Minikube**
O Minikube será iniciado com **2 nós, 4 CPUs, 10GB de memória e 10GB de disco**:
```bash
minikube start --nodes=2 --cpus=4 --memory=10000 --disk-size=10G --driver=docker --kubernetes-version=v1.28.3
```

### **2️⃣ Habilitar o MetalLB**
Habilita o **MetalLB** para LoadBalancer no cluster:
```bash
minikube addons enable metallb
```

Define um intervalo de IPs baseado no IP do Minikube:
```yaml
address-pools:
- name: default
  protocol: layer2
  addresses:
  - 192.168.49.200-192.168.49.210
```

### **3️⃣ Instalar o Istio**
Baixa e instala o Istio **versão 1.24.2**:
```bash
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-1.24.2/bin:$PATH
istioctl install --set profile=demo -y
```

Verifica se o **Ingress Gateway** pegou um **External IP**:
```bash
kubectl get svc -n istio-system istio-ingressgateway
```

### **4️⃣ Criar Namespaces e Aplicar Configuração do Istio Gateway**
```bash
kubectl apply -f k8s/config/namespaces.yml
kubectl apply -f k8s/config/istio/gateway.yml
```

### **5️⃣ Implantar os Serviços no Cluster**

#### 🔹 Implantação do **Banco de Dados**:
```bash
kubectl apply -f k8s/db/mysql-configmap.yml
kubectl apply -f k8s/db/mysql-deployment.yml
```

#### 🔹 Implantação da **Mensageria (RabbitMQ)**:
```bash
kubectl apply -f k8s/messaging/deployment.yml
kubectl apply -f k8s/messaging/virtual-service.yml
```

#### 🔹 Implantação do **Backend (Parking Service)**:
```bash
kubectl apply -f k8s/parking/configmap.yml
kubectl apply -f k8s/parking/deployment.yml
kubectl apply -f k8s/parking/virtual-service.yml
kubectl apply -f k8s/parking/destination-rule.yml
```

### **6️⃣ Instalar e Configurar o Argo CD**

#### 🔹 Criar o Namespace do Argo CD e instalar com Helm:
```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd
```

#### 🔹 Alterar o Service do ArgoCD para LoadBalancer:
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

### **7️⃣ Instalar o Argo Rollouts**

Criar o namespace e instalar com Helm:
```bash
kubectl create namespace argo-rollouts
helm install argo-rollouts argo/argo-rollouts --namespace argo-rollouts
```

Habilitar suporte ao **Argo Rollouts no Argo CD**:
```bash
kubectl patch configmap/argocd-cm -n argocd --type merge -p '{"data": {"resource.customizations.health.argoproj.io_Rollout": "# Health check for Argo Rollouts\nhs = {} hs.status = \"Healthy\" if obj.status and obj.status.readyReplicas == obj.status.replicas else \"Progressing\"\nhs"}}'
```

Reiniciar o **Argo CD** para aplicar as mudanças:
```bash
kubectl rollout restart deployment argocd-server -n argocd
```

### **8️⃣ Recuperar Credenciais do Argo CD**

O Argo CD gera um **password inicial** para login. Para recuperá-lo:
```bash
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode)
echo "Senha do ArgoCD: $ARGOCD_PASSWORD"
```

### **9️⃣ Recuperar External IP do Cluster**

O script aguarda até que o **MetalLB** atribua um External IP:
```bash
while [ -z "$EXTERNAL_IP" ]; do
  echo "⏳ Aguardando MetalLB atribuir um External IP..."
  sleep 5
  EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done
echo "O External IP é: $EXTERNAL_IP"
```

---

## ✅ **Acessando os Serviços**

### **📌 Acessar o Argo CD**
Após a instalação, o Argo CD estará disponível em:
```
http://$ARGOCD_EXTERNAL_IP
```
Usuário: **admin**
Senha: **$ARGOCD_PASSWORD**

### **📌 Acessar o Ambiente**
A aplicação pode ser acessada via:
```
http://$EXTERNAL_IP/frontend/nginx
```

Se estiver usando Minikube, adicione ao `/etc/hosts`:
```bash
echo "$EXTERNAL_IP frontend.example.com" | sudo tee -a /etc/hosts
```

Agora você pode acessar:
```
http://frontend.example.com
```

---

## 🎯 **Conclusão**
Este script configura automaticamente um ambiente Kubernetes com **Minikube, MetalLB, Istio, Argo CD e Argo Rollouts**, permitindo que você **implante e gerencie aplicações de maneira automatizada e escalável**.

Agora seu ambiente está **pronto para deploys automatizados com GitOps e rollouts progressivos!** 🚀🔥

