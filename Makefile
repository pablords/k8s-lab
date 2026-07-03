# Makefile para orquestrar instalação do cluster passo a passo

.PHONY: all prepare certmanager-otel observability monitoring deploy-marketplace dashboard delete help

all: prepare certmanager-otel observability monitoring deploy-marketplace

prepare:
	@echo "🚀 Etapa 1 - Preparar cluster Kubernetes e Istio"
	bash scripts/01_prepare_cluster.sh

certmanager-otel:
	@echo "🚀 Etapa 2 - Instalar cert-manager e OpenTelemetry Operator"
	bash scripts/03_install_certmanager_otel.sh

observability:
	@echo "🚀 Etapa 3 - Instalar OpenSearch e Jaeger"
	bash scripts/04_install_opensearch_observability.sh

monitoring:
	@echo "🚀 Etapa 3.5 - Instalar Prometheus, Grafana e Fluent-Bit"
	bash scripts/05_install_prometheus_grafana_fluentbit.sh

deploy-marketplace:
	@echo "🚀 Etapa 4 - Implantar aplicações do Marketplace"
	bash scripts/05_deploy_marketplace.sh

delete:
	@echo "🗑️  Deletando todos os recursos do cluster"
	minikube delete --all
	docker network disconnect -f minikube registry >/dev/null 2>&1 || true
	docker network rm minikube >/dev/null 2>&1 || true

dashboard:
	@echo "📊 Abrindo o Minikube Dashboard (ou exibindo o link)..."
	minikube dashboard --url

help:
	@echo ""
	@echo "✨ Makefile - Playbook Kubernetes ✨"
	@echo ""
	@echo "Targets disponíveis:"
	@echo "  make prepare            - Etapa 1: Preparar cluster (Minikube, MetalLB, Istio)"
	@echo "  make certmanager-otel   - Etapa 2: Instalar cert-manager e OpenTelemetry Operator"
	@echo "  make observability      - Etapa 3: Instalar OpenSearch e Jaeger"
	@echo "  make monitoring         - Etapa 3.5: Instalar Prometheus, Grafana e Fluent-Bit"
	@echo "  make deploy-marketplace - Etapa 4: Implantar ecossistema do Marketplace"
	@echo "  make dashboard          - Exibir o link e abrir o Dashboard do Kubernetes"
	@echo "  make delete             - Deletar e destruir todo o cluster local"
	@echo ""
	@echo "Para executar tudo em sequência:"
	@echo "  make all"
	@echo ""
