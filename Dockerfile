# syntax=docker/dockerfile:1
# ============================================================================
# OpenChamber - community Docker image (thin image: npm packages, no source build)
# Upstream: https://github.com/openchamber/openchamber (v2.4.0)
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

# Copy cloudflared binary (từ upstream, phục vụ Cloudflare Tunnel / remote access)
COPY --from=cloudflare/cloudflared:latest /usr/local/bin/cloudflared /usr/local/bin/cloudflared

# Khai báo môi trường tập trung (kèm các biến định tuyến Browser/Chromium)
ENV PATH="/usr/local/bin:/usr/bin:${PATH}" \
    OPENCHAMBER_PORT=8080 \
    OPENCHAMBER_HOST=0.0.0.0 \
    NODE_ENV=production \
    DEBIAN_FRONTEND=noninteractive \
    OPENCHAMBER_CHROME_PATH="/usr/local/bin/chromium" \
    CHROME_BIN="/usr/local/bin/chromium" \
    CHROME_PATH="/usr/local/bin/chromium" \
    PUPPETEER_EXECUTABLE_PATH="/usr/local/bin/chromium" \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="/usr/local/bin/chromium"

WORKDIR /root

# GOM LAYER: Cài hệ thống tools, Chromium + fonts (phục vụ browser & CDP tooling),
# Python 3.12 (uv), và cài OpenChamber + OpenCode agent qua NPM.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git ssh build-essential tini procps unzip psmisc \
        chromium fonts-liberation fonts-noto-color-emoji \
    && uv python install 3.12 \
    && npm install --global --no-audit --no-fund \
        "opencode-ai@${OPENCODE_VERSION}" \
        "@openchamber/web@${OPENCHAMBER_VERSION}" \
    && npm ls -g --depth=0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /root/.npm

# Wrapper scripts cho Chromium chạy an toàn trong môi trường container (root / limited /dev/shm)
RUN printf '#!/bin/sh\nexec /usr/bin/chromium --no-sandbox --disable-dev-shm-usage "$@"\n' > /usr/local/bin/chromium \
    && chmod +x /usr/local/bin/chromium \
    && ln -s /usr/local/bin/chromium /usr/local/bin/google-chrome \
    && ln -s /usr/local/bin/chromium /usr/local/bin/chrome

# Entrypoint: foreground + SSH key + OPENCODE_CONFIG_DIR + cache cleanup + OH_MY_OPENCODE
COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Metadata cho GHCR
LABEL org.opencontainers.image.title="OpenChamber (community)" \
      org.opencontainers.image.description="OpenChamber web UI + OpenCode agent + Chromium - npm thin image" \
      org.opencontainers.image.source="https://github.com/hung319/openchamber-docker" \
      org.opencontainers.image.version="${OPENCHAMBER_VERSION}"

EXPOSE 8080

# Healthcheck dựa trên endpoint /health của OpenChamber server
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${OPENCHAMBER_PORT}/health" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
