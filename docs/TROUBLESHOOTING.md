# 🔍 Troubleshooting - Solução de Problemas do Ambiente K8s

Este guia documenta problemas comuns que podem ocorrer no provisionamento e monitoramento do ambiente local de Kubernetes (Minikube) do Marketplace Search System, junto com suas respectivas soluções.

---

## 📋 Índice
1. [Erro de Inicialização do Minikube (Container Runtime / cri-dockerd)](#1-erro-de-inicialização-do-minikube-container-runtime-cri-dockerd)
2. [Conexão e Inicialização do Local Registry Falhando](#2-conexão-e-inicialização-do-local-registry-falhando)
3. [Dashboards de Monitoramento (Kafka / OpenSearch) Sem Dados (No Data)](#3-dashboards-de-monitoramento-kafka--opensearch-sem-dados-no-data)
4. [HPA Não Escala os Pods (Métricas `<unknown>`)](#4-hpa-não-escala-os-pods-métricas-unknown)
5. [Painel de Contagem de Pods Sempre Mostra `1`](#5-painel-de-contagem-de-pods-sempre-mostra-1)
6. [Alterações nos Dashboards do Grafana Não Aparecem](#6-alterações-nos-dashboards-do-grafana-não-aparecem)

---

## 1. Erro de Inicialização do Minikube (Container Runtime / cri-dockerd)

### ❌ Sintoma
Ao iniciar o Minikube via `make prepare` ou diretamente via CLI, o processo falha com a seguinte mensagem de erro:
```text
Exiting due to RUNTIME_ENABLE: Failed to enable container runtime: sudo service cri-docker.socket restart: Process exited with status 5
Failed to restart cri-docker.socket.service: Unit cri-docker.socket.service not found.
```

### 🔍 Causa
Este erro ocorre devido a uma incompatibilidade entre a versão antiga do binário `minikube` instalada no host (ex: v1.30.1) e a versão alvo do Kubernetes (v1.28.3) ou do runtime docker necessário.

### ✔️ Solução
Atualize o Minikube para a versão mais recente (ex: v1.38.1 ou superior) no seu host local:

1. **Baixe a versão mais recente do Minikube:**
   ```bash
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   ```

2. **Instale o novo binário (no PATH do seu usuário ou globalmente):**
   * *Localmente (Recomendado se não tiver privilégios root diretos):*
     ```bash
     mkdir -p ~/.local/bin
     install minikube-linux-amd64 ~/.local/bin/minikube
     rm minikube-linux-amd64
     ```
   * *Globalmente:*
     ```bash
     sudo install minikube-linux-amd64 /usr/local/bin/minikube
     rm minikube-linux-amd64
     ```

3. **Destrua o cluster antigo e recrie:**
   ```bash
   minikube delete --all
   make prepare
   ```

---

## 2. Conexão e Inicialização do Local Registry Falhando

### ❌ Sintoma
Ao executar o script de preparação (`make prepare`), o console exibe um erro de rede do Docker ao tentar levantar o container de registro local:
```text
Error response from daemon: failed to set up container networking: Could not attach to network <network_id>: rpc error: code = NotFound desc = network <network_id> not found
Error: failed to start containers: registry
```

### 🔍 Causa
O container `registry` existente na máquina host está vinculado a uma rede virtual antiga do Docker (`minikube`) que foi deletada quando o cluster foi recriado ou limpo.

### ✔️ Solução
Remova o container de registro desatualizado para que o script de preparação possa recriá-lo conectado à rede correta do novo cluster:

1. **Delete o container órfão:**
   ```bash
   docker rm -f registry
   ```

2. **Execute a preparação novamente:**
   ```bash
   make prepare
   ```

---

## 3. Dashboards de Monitoramento (Kafka / OpenSearch) Sem Dados (No Data)

### ❌ Sintoma
Os dashboards no Grafana para **Kafka - Cluster Health** e/ou **OpenSearch - Cluster Health** abrem normalmente, mas todos os painéis e gráficos exibem a mensagem **"No Data"** (ou sem dados disponíveis).

### 🔍 Causa
Como o cluster foi recriado do zero, os componentes de exportação de métricas (`kafka-exporter` e `opensearch-exporter`) que coletam os dados de saúde não foram provisionados. Isso ocorre porque o script automático de deploy do marketplace busca apenas por arquivos chamados exatamente `manifest.yml`:
```bash
find apps/marketplace -name "manifest.yml" -exec kubectl apply -f {} \;
```
Arquivos de integrações e exporters adicionais como `kafka-exporter.yml` e `opensearch-exporter.yml` ficam de fora desse deploy automático.

### ✔️ Solução
Aplique manualmente os arquivos de manifesto dos exportadores e reinicie o Grafana para atualizar os dashboards:

1. **Suba o exportador do Kafka:**
   ```bash
   kubectl apply -f apps/marketplace/integration/kafka-exporter.yml
   ```

2. **Suba o exportador do OpenSearch:**
   ```bash
   kubectl apply -f k8s/observability/opensearch-exporter.yml
   ```

3. **Reinicie o Grafana (para forçar o recarregamento rápido):**
   ```bash
   kubectl rollout restart deployment/grafana -n observability
   ```

4. **Verifique se os pods estão saudáveis:**
   ```bash
   kubectl get pods -n marketplace -l app=kafka-exporter
   ```
   *O status deve ser `Running` e pronto (`1/1 Ready`).*

---

## 4. HPA Não Escala os Pods (Métricas `<unknown>`)

### ❌ Sintoma
Os pods atingem 90–100% de CPU mas o número de réplicas permanece inalterado. Ao checar o HPA, a coluna `TARGETS` exibe `<unknown>/70%` para todos os serviços:
```bash
kubectl get hpa -n marketplace
# NAME                 REFERENCE                TARGETS         MINPODS   MAXPODS   REPLICAS
# catalog-service-hpa  Deployment/catalog-service  <unknown>/70%   2         5         2
```

### 🔍 Causa
O **Metrics Server** não está instalado ou não está habilitado no Minikube. O HPA depende da Metrics API (`metrics.k8s.io`) para ler o consumo de CPU e Memória dos pods. Sem ela, a métrica aparece como `<unknown>` e o HPA nunca dispara o scale-out.

### ✔️ Solução
1. **Habilite o addon do Metrics Server:**
   ```bash
   minikube addons enable metrics-server
   ```
2. **Aguarde ~60 segundos** para que ele colete as primeiras amostras dos nós e pods.
3. **Verifique se os targets mudaram:**
   ```bash
   kubectl get hpa -n marketplace
   # Os valores de TARGETS devem sair de <unknown> para ex: 494%/70%
   kubectl top pods -n marketplace
   ```

> ⚠️ **Para persistir após recriar o cluster:** Adicione `minikube addons enable metrics-server` ao script `scripts/01_prepare_cluster.sh` (já adicionado).

---

## 5. Painel de Contagem de Pods Sempre Mostra `1`

### ❌ Sintoma
O painel **"Quantidade de Pods por Aplicação"** no dashboard `Marketplace Search System - Overview` sempre exibe o valor `1` para cada serviço, mesmo quando o HPA escalou para 5 réplicas.

### 🔍 Causa
O Prometheus usa `static_configs` com o DNS do **Kubernetes Service** (ex: `search-service.marketplace:8083`), não de pods individuais. Um Service Kubernetes age como load balancer — há **um único target de scraping** para todas as réplicas. Portanto, a query `sum(up{job="search-service"})` sempre retorna `1` (um target), independentemente de quantos pods estão rodando.

### ✔️ Solução
A solução é adicionar jobs de **Kubernetes Pod Discovery** (`kubernetes_sd_configs` com `role: pod`) no `prometheus.yml`, que fazem o Prometheus descobrir e scraper **cada pod individualmente**. Isso já foi aplicado no arquivo `k8s/observability/prometheus/prometheus.yml` com os jobs `*-pods`:
```yaml
- job_name: 'pods-search-service'
  kubernetes_sd_configs:
    - role: pod
      namespaces:
        names: ['marketplace']
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app]
      action: keep
      regex: search-service
    - source_labels: [__meta_kubernetes_pod_name]
      target_label: pod
    ...
```
E as queries do dashboard foram corrigidas de `sum(up{job="..."})`  para `count(up{job="...-pods"} == 1)`.

Para reaplicar ao cluster após editar o `prometheus.yml`:
```bash
kubectl create configmap prometheus-config \
  --from-file=prometheus.yml=k8s/observability/prometheus/prometheus.yml \
  -n observability --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/prometheus -n observability
```

---

## 6. Alterações nos Dashboards do Grafana Não Aparecem

### ❌ Sintoma
Após editar um arquivo JSON em `k8s/observability/grafana/dashboards/`, as mudanças não aparecem no Grafana, mesmo após reiniciá-lo.

### 🔍 Causa
Os dashboards são carregados no Grafana via um **ConfigMap Kubernetes** (`grafana-dashboards`). Editar o arquivo JSON localmente **não atualiza o ConfigMap no cluster** automaticamente. O Grafana monta o ConfigMap como volume e só lê os arquivos no momento em que o pod é iniciado.

### ✔️ Solução
Sempre que editar qualquer dashboard JSON, execute o seguinte para recriar o ConfigMap e reiniciar o Grafana:
```bash
kubectl delete configmap grafana-dashboards -n observability --ignore-not-found
kubectl create configmap grafana-dashboards \
  -n observability \
  --from-file=k8s/observability/grafana/dashboards/
kubectl rollout restart deployment/grafana -n observability
```
O mesmo se aplica às configurações do Prometheus (`prometheus-config`). O padrão de atualização é sempre: **editar o arquivo local → recriar o ConfigMap → reiniciar o deployment**.
