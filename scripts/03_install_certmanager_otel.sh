#!/bin/bash
set -e

echo "🚀 Instalando cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

kubectl rollout status deployment cert-manager -n cert-manager
kubectl rollout status deployment cert-manager-cainjector -n cert-manager
kubectl rollout status deployment cert-manager-webhook -n cert-manager

echo "✅ cert-manager pronto."

echo "🚀 Instalando OpenTelemetry Operator..."
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/download/v0.90.0/opentelemetry-operator.yaml

kubectl rollout status deployment opentelemetry-operator-controller-manager -n opentelemetry-operator-system

echo "✅ OpenTelemetry Operator instalado!"
