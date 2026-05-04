#!/bin/bash
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-ap-python-launcher}"
DRIVER="${MINIKUBE_DRIVER:-docker}"
CPUS="${MINIKUBE_CPUS:-4}"
MEMORY="${MINIKUBE_MEMORY:-8192}"
K8S_VERSION="${MINIKUBE_K8S_VERSION:-}"
METALLB_MANIFEST_URL="https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml"
METALLB_POOL_FILE="/workspace/compose/local/minikube/metallb-pool.yaml"

log_debug() {
  echo "[minikube-debug] $*"
}

run_docker_diagnostics() {
  if [[ "${DRIVER}" != "docker" ]]; then
    return
  fi

  log_debug "uid=$(id -u) gid=$(id -g) pwd=$(pwd)"
  log_debug "docker_socket_present=$(if [[ -S /var/run/docker.sock ]]; then echo yes; else echo no; fi)"
  log_debug "docker_cli=$(command -v docker || echo missing)"
  docker version || true
  docker info || true
  docker ps -a --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}' || true
  minikube status --profile "${PROFILE}" || true
}

cleanup_diagnostics() {
  if [[ "${DRIVER}" != "docker" ]]; then
    return
  fi

  log_debug "collecting post-failure docker diagnostics"
  docker ps -a --no-trunc --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}' || true
  docker inspect "${PROFILE}" || true
  docker logs "${PROFILE}" || true
  docker exec "${PROFILE}" systemctl --no-pager --full status kubelet || true
  docker exec "${PROFILE}" journalctl --no-pager -u kubelet -n 200 || true
  docker exec "${PROFILE}" crictl ps -a || true
}

reset_existing_profile() {
  if [[ "${DRIVER}" != "docker" ]]; then
    return
  fi

  log_debug "deleting any existing minikube profile/container for ${PROFILE}"
  minikube delete --profile "${PROFILE}" || true
  docker rm -f "${PROFILE}" || true
}

START_ARGS=(
  start
  "--profile=${PROFILE}"
  "--driver=${DRIVER}"
  "--cpus=${CPUS}"
  "--memory=${MEMORY}"
)

if [[ "${DRIVER}" == "docker" && "$(id -u)" == "0" ]]; then
  START_ARGS+=("--force")
fi

if [[ -n "${K8S_VERSION}" ]]; then
  START_ARGS+=("--kubernetes-version=${K8S_VERSION}")
fi

run_docker_diagnostics
reset_existing_profile
log_debug "starting: minikube ${START_ARGS[*]}"
if ! minikube "${START_ARGS[@]}"; then
  cleanup_diagnostics
  exit 1
fi
minikube update-context --profile "${PROFILE}"

kubectl apply -f "${METALLB_MANIFEST_URL}"
kubectl wait \
  --namespace metallb-system \
  --for=condition=available deployment/controller \
  --timeout=180s
kubectl rollout status daemonset/speaker -n metallb-system --timeout=180s
kubectl apply -f "${METALLB_POOL_FILE}"

tail -f /dev/null
