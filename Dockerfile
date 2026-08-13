# syntax=docker/dockerfile:1
# ============================================================================
# OpenChamber - community Docker image (thin image: npm packages, no source build)
# Upstream: https://github.com/openchamber/openchamber  (v1.18.2, 2026-08-10)
# Yêu cầu Node.js >= 22 (engines) -> base = node:22 LTS trên Debian 13 stable
# (trixie) (khớp CI upstream release.yml dùng node-version '22').
# LƯU Ý: apt nodejs tự cài từ trixie chỉ là Node 20 -> KHÔNG đủ điều kiện,
# đây là bug tiềm ẩn của image cũ (debian:stable-slim). Phải dùng image
# node chính thức, không cài nodejs qua apt.
# ============================================================================

# Build-time version pins.
# CI (github workflow) truyền OPENCHAMBER_VERSION=<tag> để build tái lập được.
# Mặc định `latest` = hành vi cũ của image.
ARG OPENCHAMBER_VERSION=latest
ARG OPENCODE_VERSION=latest

FROM node:22-trixie-slim

ARG OPENCHAMBER_VERSION
ARG OPENCODE_VERSION

# Copy uv package manager (Dùng để cài python gọn nhất, phục vụ agent tooling)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Khai báo môi trường tập trung
ENV PATH="/usr/local/bin:/usr/bin:${PATH}" \
    OPENCHAMBER_PORT=8080 \
    OPENCHAMBER_HOST=0.0.0.0 \
    NODE_ENV=production \
    DEBIAN_FRONTEND=noninteractive

WORKDIR /root

# GOM LAYER: Cài hệ thống tools, Python 3.12 (uv), và cài OpenChamber + OpenCode
# agent qua NPM (bản build sẵn, không cần compile source).
# Nodejs 22 + npm đã có sẵn trong base image node:22-trixie-slim.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git ssh build-essential tini procps unzip psmisc \
    && uv python install 3.12 \
    && npm install --global --no-audit --no-fund \
        "opencode-ai@${OPENCODE_VERSION}" \
        "@openchamber/web@${OPENCHAMBER_VERSION}" \
    && npm ls -g --depth=0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /root/.npm

# Entrypoint: foreground + SSH key + OPENCODE_CONFIG_DIR + cache cleanup
COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Metadata cho GHCR
LABEL org.opencontainers.image.title="OpenChamber (community)" \
      org.opencontainers.image.description="OpenChamber web UI + OpenCode agent - npm thin image" \
      org.opencontainers.image.source="https://github.com/hung319/openchamber-docker" \
      org.opencontainers.image.version="${OPENCHAMBER_VERSION}"

EXPOSE 8080

# Healthcheck dựa trên endpoint /health của OpenChamber server (thêm 2026-08)
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${OPENCHAMBER_PORT}/health" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
