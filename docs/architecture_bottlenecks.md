# Análise de Gargalos e Resiliência sob Alta Concorrência

Este documento consolida os principais aprendizados e diagnósticos de gargalos realizados durante os testes de carga com o K6 no **Marketplace Search System**. A bateria de testes revelou uma série de comportamentos sistêmicos que ocorrem exclusivamente em cenários de alta concorrência.

## 1. Race Conditions em Middlewares (API Gateway)
Durante os testes, observamos que o `catalog-service` (Java) estava rejeitando requisições válidas com erro `400 Bad Request` ("Sum of review types must equal total reviews"), mesmo o K6 gerando os payloads matematicamente corretos. 

**O Diagnóstico:** 
O middleware de validação do API Gateway (escrito em Go) estava instanciando um ponteiro único para o template do DTO (`models.Product`) na memória. Quando `c.ShouldBindJSON()` era chamado, as centenas de requisições concorrentes injetadas pelo K6 **sobrescreviam os dados umas das outras** na memória compartilhada (Data Race). Isso causava a "perda" de campos (como `negative_reviews` chegando como `0`), violando a regra de domínio na ponta do Java.

**A Solução:**
Refatoramos o middleware para usar *Reflection* (`reflect.New()`), garantindo a alocação de um novo endereço de memória (uma nova instância de `Product`) para cada requisição concorrente.

## 2. Métricas, K6 e Prometheus Remote Write
Encontramos dificuldades de visualização nos painéis do Grafana referentes a latências (P50, P95, P99).

**O Diagnóstico:**
- Inicialmente, o K6 estava utilizando *Native Histograms* para enviar dados ao Prometheus. Isso causava erros `500 Internal Server Error` na gravação remota do Prometheus, devido à sobrecarga ou incompatibilidade.
- Ao desativar os Native Histograms para resolver o crash do Prometheus, os percentis pararam de aparecer. Descobrimos que, sem Native Histograms, o K6 muda o formato de exportação de sumarização `{quantile="0.95"}` para métricas separadas com sufixos `_p95`.

**A Solução:**
- Configuramos explicitamente o K6 para exportar todas as métricas de tendência desejadas (`K6_PROMETHEUS_RW_TREND_STATS="p(50),p(95),p(99),avg,min,max"`).
- Atualizamos as queries do Grafana para consumir os nomes literais exportados pelo K6 (ex: `k6_http_req_duration_p95`).

## 3. Estrangulamento de CPU e Pool de Conexões (PostgreSQL)
Quando aumentamos a carga para 550 VUs (Virtual Users), começamos a receber muitos erros `502 Bad Gateway` e `503 Upstream Connect Error`.

**O Diagnóstico:**
1. **Falta de CPU no BD:** O pod do PostgreSQL possuía um limite (`limits.cpu`) de apenas `500m` (meia CPU). 
2. **Saturação do Pool:** Com o cluster escalado para 5 pods do `catalog-service` — cada um configurado com um HikariCP (pool de conexões) de tamanho 100 —, o banco sofreu um ataque de até 500 conexões simultâneas tentando fazer `INSERTs`.
3. **Bloqueio de Threads:** Sem CPU para processar, o banco enfileirou as transações. O que deveria durar 5 milissegundos passou a durar até 24 segundos. Consequentemente, todas as 100 threads do Tomcat no Java ficaram travadas aguardando o HikariCP.

## 4. O Efeito Cascata (Cascading Failure) provocado pela Liveness Probe
O pior efeito do estrangulamento do banco foi a queda dos pods.

**O Diagnóstico:**
Com todas as threads presas no banco, o Kubernetes executava a verificação de saúde (`Liveness Probe`) na rota `/api/v1/actuator/health`. Por padrão, o Spring Boot checa a conexão com o banco para se declarar "Saudável". Como o pool estava cheio e o banco lento, a checagem sofria timeout (1s).
O Kubernetes entendeu que a aplicação estava morta e enviou um **`SIGTERM` (Exit Code 143)**. 
A morte súbita do Pod cancelava todas as conexões HTTP em andamento, fazendo com que o API Gateway retornasse `502` e o Ingress (Envoy/NGINX) retornasse `503`.

**A Solução:**
1. **Liveness Probe Inteligente:** Alteramos a rota do probe no Kubernetes para `/api/v1/actuator/health/liveness`. Esta rota (nativa no Spring Boot para K8s) avisa o cluster apenas se o processo da JVM/Tomcat estiver vivo e processando, ignorando a indisponibilidade temporária de recursos externos como o Banco de Dados. O banco lento não resulta mais na morte do Pod.
2. **Readiness Probe:** Isolamos a checagem de tráfego na `/api/v1/actuator/health/readiness`. Se o banco travar, o Pod simplesmente para de receber novas requisições até se recuperar, mas não é morto no meio do processo.
3. **Calibragem de Bulkhead (Semaphore):** Reduzimos o semáforo de concorrência máxima de 100 para `50` por Pod. Assim, a aplicação atua como um escudo para o banco de dados. Se o tráfego exceder o que a infraestrutura suporta, o Java rejeita o excesso elegante e imediatamente com um **`429 Too Many Requests`**, mantendo o sistema em pé e o banco de dados respirando.

---
> **💡 Regra de Ouro de Arquitetura:**
> Nunca aponte uma *Liveness Probe* de um container para uma dependência externa (banco de dados, cache, api terceira) caso você não deseje que a lentidão desse recurso resulte no reinício abrupto de toda a sua aplicação.
