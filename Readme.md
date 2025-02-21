# k8s-lab

Este repositório contém um ambiente Kubernetes completo utilizando **Minikube**, **MetalLB**, **Istio**, **Argo CD** e **Argo Rollouts** para gerenciamento e implantação progressiva de aplicações.

## 🚀 Configuração Automática do Cluster

Para configurar todo o ambiente automaticamente, execute:

```bash
chmod +x setup.sh
./setup.sh
```

O script **setup.sh** irá configurar todo o cluster Kubernetes, incluindo MetalLB, Istio, Argo CD e Argo Rollouts.

---

## 📌 Tecnologias Utilizadas

- **Minikube** - Cria e gerencia um cluster Kubernetes local.
- **MetalLB** - Load Balancer para Kubernetes local.
- **Istio** - Service Mesh para controle de tráfego e segurança.
- **Argo CD** - Gerenciamento de implantação GitOps.
- **Argo Rollouts** - Estratégias avançadas de rollout para Kubernetes.

---

## 🔥 Etapas do Setup

### 1️⃣ Iniciar Minikube

O cluster Kubernetes é iniciado com **2 nós**, **4 CPUs**, **10GB de Memória** e **10GB de disco**:

```bash
minikube start --nodes=2 --cpus=4 --memory=10000 --disk-size=10G --driver=docker --kubernetes-version=v1.28.3
```

### 2️⃣ Habilitar MetalLB

MetalLB é ativado para fornecer suporte a LoadBalancer:

```bash
minikube addons enable metallb
```

O **intervalo de IPs** é configurado dinamicamente com base no IP do Minikube.

### 3️⃣ Instalar Istio

Baixa e instala o Istio no cluster:

```bash
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-1.24.2/bin:$PATH
istioctl install --set profile=demo -y
```

O **Istio Gateway** é configurado para rotear tráfego:

```bash
kubectl apply -f k8s/config/istio/gateway.yml
```

### 4️⃣ Instalar Argo CD

Instalação do Argo CD para gerenciamento de implantações:

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

A senha padrão do ArgoCD pode ser obtida com:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode
```

### 5️⃣ Instalar Argo Rollouts

Adiciona suporte a implantações canary e blue-green:

```bash
kubectl create namespace argo-rollouts
helm install argo-rollouts argo/argo-rollouts --namespace argo-rollouts
kubectl apply -f k8s/argo-rollouts/service.yml
kubectl apply -f k8s/argo-rollouts/vs.yml
```

**Configuração do health check do Argo CD para Rollouts:**

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data": {"resource.customizations.health.argoproj.io_Rollout": "# Health check for Argo Rollouts\nhs = {} hs.status = \"Healthy\" if obj.status and obj.status.readyReplicas == obj.status.replicas else \"Progressing\"\nhs"}}'
```

**Reinicie o servidor do Argo CD para aplicar as configurações:**

```bash
kubectl rollout restart deployment argocd-server -n argocd
```

### 6️⃣ Implantar Aplicativos via Argo CD

As aplicações backend, banco de dados e frontend são implantadas automaticamente via Argo CD:

```bash
kubectl apply -f apps/backend/parking/app.yml
kubectl apply -f apps/data/db/app.yml
kubectl apply -f apps/data/messaging/app.yml
kubectl apply -f apps/frontend/nginx/app.yml
```

---

## 🎯 **Acessando o Ambiente**

### 🔹 **Acessar Argo CD**

Obtenha o **IP Externo** do Argo CD:

```bash
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Depois, acesse no navegador:

```
http://<EXTERNAL_IP>
```

Usuário: `admin`  
Senha: Obtida pelo comando:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 --decode
```

### 🔹 **Acessar o Nginx**

Obtenha o **EXTERNAL-IP** do Istio:

```bash
kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Acesse no navegador:

```
http://<EXTERNAL_IP>/frontend/nginx
```

### 🔹 **Gerenciar Argo Rollouts**

Acesse o painel do Argo Rollouts com:

```bash
kubectl argo rollouts dashboard -n argo-rollouts
```

Valide o estado do Rollout:

```bash
kubectl argo rollouts get rollout nginx -n frontend
```

---

## 🛠 **Testando um Deploy Canary**

Atualize a imagem do Nginx para uma nova versão:

```bash
kubectl argo rollouts set image nginx nginx=nginx:1.21 -n frontend
```

Isso iniciará um rollout gradual com pesos configurados (20% → 50% → 100%).

**Acompanhe a progressão do rollout:**

```bash
kubectl argo rollouts get rollout nginx -n frontend --watch
```

Se precisar reverter para a versão estável anterior:

```bash
kubectl argo rollouts abort nginx -n frontend
```

---

## 🎉 **Conclusão**

Agora você tem um ambiente Kubernetes **completo**, incluindo:

✅ **Gerenciamento GitOps com Argo CD**  
✅ **Implantação progressiva com Argo Rollouts**  
✅ **Balanceamento de carga com MetalLB**  
✅ **Controle de tráfego e Service Mesh com Istio**  

