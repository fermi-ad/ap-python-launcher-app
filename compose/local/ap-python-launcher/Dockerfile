# syntax=docker/dockerfile:1

FROM ghcr.io/cirruslabs/flutter:stable

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    KUBECONFIG=/workspace/.kube/config \
    MINIKUBE_HOME=/workspace/.minikube \
    PATH="/root/.local/bin:/workspace/.venv/bin:${PATH}"

WORKDIR /workspace

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    make \
    python3 \
    python3-venv \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

COPY pyproject.toml uv.lock README.md LICENSE ./
COPY src/ ./src/
COPY tests/ ./tests/
COPY frontend/pubspec.yaml frontend/pubspec.lock frontend/analysis_options.yaml ./frontend/

RUN uv sync --frozen
RUN cd frontend && flutter pub get

COPY . .

RUN mkdir -p /workspace/.kube /workspace/.minikube

EXPOSE 8000 5173

CMD ["bash", "-lc", "uv sync && cd frontend && flutter pub get && cd /workspace && /workspace/.venv/bin/uvicorn ap_python_launcher.server:app --host 0.0.0.0 --port ${PORT:-8000} --reload"]
