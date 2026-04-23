# syntax=docker/dockerfile:1

# --- Stage 1: build Flutter web assets ---
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /build
COPY frontend/ /build/frontend/
RUN cd /build/frontend \
  && flutter pub get \
  && flutter build web --release --wasm

# --- Stage 2: Python runtime ---
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# System deps
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package installer)
RUN python -m pip install --upgrade pip \
  && python -m pip install uv

# Copy everything setuptools needs to resolve the src layout
COPY pyproject.toml /app/pyproject.toml
COPY uv.lock /app/uv.lock
COPY README.md /app/README.md
COPY LICENSE /app/LICENSE
COPY src/ /app/src/

# Embed Flutter build output into the package before install so it is
# included in the installed package at Path(__file__).parent / "static"
COPY --from=flutter-builder /build/frontend/build/web/ /app/src/ap_python_launcher/static/

RUN uv sync --no-dev --frozen

# Create and switch to a non-root user
RUN useradd -r -u 10001 -g root appuser \
  && chown -R 10001:0 /app
USER 10001

EXPOSE 8000

# Run FastAPI via Uvicorn
CMD ["/app/.venv/bin/python", "-m", "uvicorn", "ap_python_launcher.server:app", "--host", "0.0.0.0", "--port", "8000"]
