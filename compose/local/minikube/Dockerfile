# syntax=docker/dockerfile:1

FROM debian:bookworm-slim

ARG KUBECTL_VERSION=v1.30.1
ARG MINIKUBE_VERSION=v1.35.0
ARG HELM_VERSION=v3.17.3

ENV KUBECONFIG=/workspace/.kube/config \
    MINIKUBE_HOME=/workspace/.minikube

WORKDIR /workspace

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    apt-transport-https \
    bash \
    ca-certificates \
    conntrack \
    curl \
    docker.io \
    git \
    iproute2 \
    iptables \
    openssh-client \
    socat \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
  && chmod +x /usr/local/bin/kubectl

RUN curl -fsSL "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64" -o /usr/local/bin/minikube \
  && chmod +x /usr/local/bin/minikube

RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz \
  && tar -xzf /tmp/helm.tgz -C /tmp \
  && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
  && chmod +x /usr/local/bin/helm \
  && rm -rf /tmp/helm.tgz /tmp/linux-amd64

RUN mkdir -p /workspace/.kube /workspace/.minikube

COPY compose/local/minikube/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

CMD ["/usr/local/bin/start.sh"]
