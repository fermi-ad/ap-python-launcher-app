# syntax=docker/dockerfile:1

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

# Install python deps first (better layer caching)
COPY pyproject.toml /app/pyproject.toml
COPY uv.lock /app/uv.lock

RUN uv sync --no-dev --frozen

# Copy the source last
COPY ap_launcher/ /app/ap_launcher/
COPY README.md /app/README.md

# Install the project itself into the same venv (deps already installed)
RUN uv pip install --no-deps .

# Create and switch to a non-root user
RUN useradd -r -u 10001 -g root appuser \
  && chown -R 10001:0 /app
USER 10001

EXPOSE 8000

# Run FastAPI via Uvicorn
CMD ["/app/.venv/bin/python", "-m", "uvicorn", "ap_launcher.server:app", "--host", "0.0.0.0", "--port", "8000"]
