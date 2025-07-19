#!/bin/bash
set -e

echo "🚀 Instalando aplicativos de demonstração OpenTelemetry..."
if ! kubectl	get namespace otel-demo &>/dev/null; then
		echo "Namespace otel-demo não encontrado. Criando namespace..."
		kubectl create namespace otel-demo
else
		echo "Namespace otel-demo já existe. Pulando criação."
fi

kubectl apply -k apps/otel-demo -n otel-demo

echo "✅ Aplicativos de demonstração OpenTelemetry instalados!"
kubectl get pods -n otel-demo
echo "⏳ Aguardando pods do OpenTelemetry demo..."
kubectl wait --for=condition=Ready pod --all -n otel-demo --timeout=300s
echo "🎉 OpenTelemetry demo pronto!"

