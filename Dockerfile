# syntax=docker/dockerfile:1

# --- Stage 1: build Flutter web assets ---
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /build
COPY frontend/ /build/frontend/
RUN cd /build/frontend \
  && flutter pub get \
  && flutter build web --release --wasm --no-web-resources-cdn --pwa-strategy=none

# --- Stage 2: build Rust backend ---
FROM rust:1.88-slim AS rust-builder

WORKDIR /build

COPY rust-backend/ /build/rust-backend/

RUN cd /build/rust-backend \
  && cargo +nightly build --release

# --- Stage 3: runtime ---
FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=rust-builder /build/rust-backend/target/release/ap-python-launcher /app/ap-python-launcher

# Serve Flutter build output from ./static
COPY --from=flutter-builder /build/frontend/build/web/ /app/static/

RUN useradd -r -u 10001 -g root appuser \
  && chown -R 10001:0 /app
USER 10001

EXPOSE 8000

ENV PORT=8000

CMD ["/app/ap-python-launcher"]
