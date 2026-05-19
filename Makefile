# Makefile para orquestrar instalação do cluster passo a passo

.PHONY: all prepare argo certmanager-otel observability monitoring deploy-marketplace delete help

all: prepare argo certmanager-otel observability monitoring deploy-marketplace

prepare:
	@echo "🚀 Etapa 1 - Preparar cluster Kubernetes e Istio"
	bash scripts/01_prepare_cluster.sh

argo:
	@echo "🚀 Etapa 2 - Instalar Argo CD e Argo Rollouts"
	bash scripts/02_install_argo.sh

certmanager-otel:
	@echo "🚀 Etapa 3 - Instalar cert-manager e OpenTelemetry Operator"
	bash scripts/03_install_certmanager_otel.sh

observability:
	@echo "🚀 Etapa 4 - Instalar OpenSearch, Dashboards e Jaeger"
	bash scripts/04_install_opensearch_observability.sh

monitoring:
	@echo "🚀 Etapa 4.5 - Instalar Prometheus, Grafana e Fluent-Bit"
	bash scripts/05_install_prometheus_grafana_fluentbit.sh

deploy-marketplace:
	@echo "🚀 Etapa 5 - Implantar aplicações do Marketplace"
	bash scripts/05_deploy_marketplace.sh

delete:
	@echo "🗑️  Deletando todos os recursos do cluster"
	minikube delete --all

help:
	@echo ""
	@echo "✨ Makefile - Playbook Kubernetes ✨"
	@echo ""
	@echo "Targets disponíveis:"
	@echo "  make prepare            - Etapa 1: Preparar cluster (Minikube, MetalLB, Istio)"
	@echo "  make argo               - Etapa 2: Instalar Argo CD e Rollouts"
	@echo "  make certmanager-otel   - Etapa 3: Instalar cert-manager e OpenTelemetry Operator"
	@echo "  make observability      - Etapa 4: Instalar OpenSearch, Dashboards e Jaeger"
	@echo "  make monitoring         - Etapa 4.5: Instalar Prometheus, Grafana e Fluent-Bit"
	@echo "  make deploy-marketplace - Etapa 5: Implantar ecossistema do Marketplace"
	@echo "  make delete             - Deletar e destruir todo o cluster local"
	@echo ""
	@echo "Para executar tudo em sequência:"
	@echo "  make all"
	@echo ""
