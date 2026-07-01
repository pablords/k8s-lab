# 📈 Capacidade e Dimensionamento do Ambiente (High Load Performance)

Este documento documenta o dimensionamento, a avaliação de capacidade e as recomendações de infraestrutura para o ecossistema do Marketplace Search System suportar altas cargas de escrita (ex: **1000 RPS** para criação de produtos).

---

## 📊 Avaliação de Capacidade do PostgreSQL (`catalog-db`)

### 1. Pool de Conexões e Limite do Banco
* **PostgreSQL Config:** `max_connections = 100`.
* **Aplicação Config (`catalog-service`):** `maximum-pool-size: 15` por réplica.
* **Auto-scaling (HPA):** O `catalog-service` está configurado para escalar de **2 a 5 réplicas**.
  * Carga mínima (2 réplicas): $2 \times 15 = 30$ conexões ativas.
  * Carga máxima (5 réplicas): $5 \times 15 = 75$ conexões ativas.
  * Componentes secundários (como o `postgres-exporter`): ~5 conexões adicionais.
* **Avaliação:** **Adequada e Segura.** O limite global do Postgres (100) é superior ao número máximo de conexões ativas do pool sob escalonamento máximo (80), eliminando a ocorrência de erros de esgotamento de conexões no banco.

### 2. Memória RAM (Tuning Postgres)
* **Recursos do Container:** Mínimo `2Gi`, Limite `4Gi`.
* **Parâmetros Otimizados:**
  * `shared_buffers = 1GB` (25% do limite físico, ideal para manter páginas de dados e índices ativos em memória).
  * `effective_cache_size = 3GB` (75% do limite físico).
  * `work_mem = 16MB` (limita o uso de memória por query temporária, evitando estouro sob concorrência).
* **Avaliação:** **Adequada.** Os parâmetros estão bem balanceados para o orçamento de 4GB de RAM.

### 3. Latência de Escrita (Discos & Commits)
* **Parâmetro:** `synchronous_commit = off`.
* **Avaliação:** **Excelente para alto throughput.** Ao desligar a sincronização física imediata com o disco, o Postgres confirma a transação assim que ela atinge o WAL Buffer na memória RAM. Isso remove o gargalo clássico de I/O em disco no caminho crítico das requisições.
* *Nota de SRE:* Existe o risco de perda de até ~200ms de transações no caso de um crash físico da máquina host do Kubernetes. Para o ambiente de lab/staging, o ganho de throughput compensa amplamente este risco.

---

## ⚠️ Gargalos Identificados sob Carga de 1000 RPS

### 1. Saturação de CPU no PostgreSQL (Logical Decoding + CDC)
* **Configuração Atual:** Limite de **2 CPUs** (`limits.cpu: "2"`).
* **Problema:** A criação de um produto executa 1000 SELECTs (idempotência) e 1000 INSERTs por segundo (2000 QPS). Cada gravação gera a atualização de **5 índices** (`idx_products_category`, `brand`, `seller`, `price`, `updated_at`). 
* Adicionalmente, com `wal_level = logical` ativado para o Debezium, o Postgres consome muita CPU para decodificar o fluxo WAL de escrita e alimentar o Kafka Connect em tempo real.
* **Diagnóstico:** **Gargalo de CPU.** 2 vCPUs atingirão 100% de uso rapidamente sob 1000 RPS de escrita e leitura contínua.

### 2. Overhead do Lock Distribuído (Redis)
* **Problema:** O caso de uso `CreateProductUseCase` realiza uma chamada síncrona ao Redis (`lockPort.acquireLock`) para garantir a idempotência antes de iniciar a transação e outra para liberar o lock após a persistência.
* **Diagnóstico:** Duas conexões de rede adicionais por request ao Redis aumentam o tempo de resposta da transação no Spring. Caso ocorra lentidão na rede, as conexões do pool de conexão do Hikari ficarão retidas por mais tempo, resultando em erros de `connection timeout` na aplicação.

### 3. Limite de Memória Física da JVM (`catalog-service`)
* **Configuração Atual:** Limite físico de **512Mi** (`limits.memory: 512Mi`), sem parâmetros JVM explícitos de limites de Heap.
* **Problema:** O Spring Boot Java operando com o agente do OpenTelemetry ativo para tracing consome rapidamente acima de 512Mi de RAM (Heap + Non-Heap + Metaspace + Overhead de telemetria) sob alta concorrência.
* **Diagnóstico:** **Risco Crítico de OOM-Kill (Exit Code 137)** por parte do Kubernetes.

---

## 🛠 Plano de Ajuste de Capacidade (Sizing Recomendado)

Para atingir e manter a marca de **1000 RPS** com segurança no ambiente Kubernetes:

### 1. Ajuste de Recursos do PostgreSQL (`catalog-db`)
Edite o arquivo `apps/marketplace/data/catalog-db/manifest.yml`:
* Aumentar o limite de CPU de `2` para **`4`** (se o host suportar):
```yaml
resources:
  requests:
    cpu: "1"
    memory: 2Gi
  limits:
    cpu: "4"
    memory: 4Gi
```

### 2. Ajuste de Recursos do Java (`catalog-service`)
Edite o arquivo `apps/marketplace/backend/catalog-service/manifest.yml`:
* Aumentar o limite de RAM de `512Mi` para **`1Gi`**:
```yaml
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```
* Configurar explicitamente as opções de heap para a JVM respeitar o container usando a variável de ambiente:
```yaml
- name: JAVA_TOOL_OPTIONS
  value: "-XX:MaxRAMPercentage=75.0"
```

### 3. Higienização e Seeding de Dados de Teste
* **Problema Comum:** O script de testes de estresse envia produtos com referências de marcas (`brand_id`), categorias (`category_id`) e vendedores (`seller_id`) que não existem na base. Isso gera exceções de chaves estrangeiras (HTTP 400), forçando rollbacks no banco que gastam CPU inutilmente.
* **Ação:** Certifique-se de popular as tabelas de dimensões (`categories`, `brands`, `sellers`) na base de dados com as chaves correspondentes **antes** de disparar o script de carga massiva.
