# Makefile para orquestrar instalação do cluster passo a passo

.PHONY: all prepare argo certmanager-otel elasticsearch deploy

all: prepare argo certmanager-otel elasticsearch deploy

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
	@echo "🚀 Etapa 4 - Instalar Elasticsearch, Kibana e APM Server"
	bash scripts/04_install_elasticsearch_kibana_apm.sh

deploy-store:
	@echo "🚀 Etapa 5 - Implantar aplicações de loja"
	bash scripts/05_deploy_apps_store.sh

deploy:
	@echo "🚀 Etapa 6 - Implantar aplicações"
	bash scripts/06_deploy_apps.sh

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
	@echo "  make observability      - Etapa 4: Instalar Elasticsearch, Kibana e APM Server"
	@echo "  make deploy-store             - Etapa 5: Implantar aplicações loja"
	@echo "  make deploy             - Etapa 6: Implantar aplicações"
	@echo ""
	@echo "Para executar tudo em sequência:"
	@echo "  make all"
	@echo ""
