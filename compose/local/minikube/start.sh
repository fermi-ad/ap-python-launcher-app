#!/bin/bash
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-ap-python-launcher}"
DRIVER="${MINIKUBE_DRIVER:-docker}"
CPUS="${MINIKUBE_CPUS:-4}"
MEMORY="${MINIKUBE_MEMORY:-8192}"
K8S_VERSION="${MINIKUBE_K8S_VERSION:-}"
METALLB_MANIFEST_URL="https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml"
METALLB_POOL_FILE="/workspace/compose/local/minikube/metallb-pool.yaml"

START_ARGS=(
  start
  "--profile=${PROFILE}"
  "--driver=${DRIVER}"
  "--cpus=${CPUS}"
  "--memory=${MEMORY}"
)

if [[ -n "${K8S_VERSION}" ]]; then
  START_ARGS+=("--kubernetes-version=${K8S_VERSION}")
fi

minikube "${START_ARGS[@]}"
minikube update-context --profile "${PROFILE}"

kubectl apply -f "${METALLB_MANIFEST_URL}"
kubectl wait \
  --namespace metallb-system \
  --for=condition=available deployment/controller \
  --timeout=180s
kubectl rollout status daemonset/speaker -n metallb-system --timeout=180s
kubectl apply -f "${METALLB_POOL_FILE}"

tail -f /dev/null
