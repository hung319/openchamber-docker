# syntax=docker/dockerfile:1
# ============================================================================
# OpenChamber - community Docker image (thin image: npm packages, no source build)
# Upstream: https://github.com/openchamber/openchamber
# Yêu cầu Node.js >= 24.14 (engines của @openchamber/web) -> base = node:24
# LTS trên Debian 13 stable (trixie). Khớp CI upstream release.yml dùng
# node-version '24' và scripts/install.sh yêu cầu MIN_NODE_VERSION=24.14.
# LƯU Ý: apt nodejs tự cài từ trixie chỉ là Node 20 -> KHÔNG đủ điều kiện,
# đây là bug tiềm ẩn của image cũ (debian:stable-slim). Phải dùng image
# node chính thức, không cài nodejs qua apt.
# ============================================================================

# Build-time version pins.
# CI (github workflow) truyền OPENCHAMBER_VERSION=<tag> và
# OPENCODE_VERSION=<tag> để build tái lập được.
# Mặc định `latest` = hành vi cũ của image.
ARG OPENCHAMBER_VERSION=latest
ARG OPENCODE_VERSION=latest

FROM node:24-trixie-slim

ARG OPENCHAMBER_VERSION
ARG OPENCODE_VERSION

# Copy uv package manager (Dùng để cài python gọn nhất, phục vụ agent tooling)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Copy cloudflared binary (từ upstream, phục vụ Cloudflare Tunnel / remote access)
COPY --from=cloudflare/cloudflared:latest /usr/local/bin/cloudflared /usr/local/bin/cloudflared

# Khai báo môi trường tập trung (kèm các biến định tuyến Browser/Chromium)
ENV PATH="/root/.local/bin:/usr/local/bin:/usr/bin:${PATH}" \
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
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="/usr/local/bin/chromium" \
    OPENCODE_BINARY="/usr/bin/opencode"

WORKDIR /root

# GOM LAYER: Cài hệ thống tools, Chromium + fonts (phục vụ browser & CDP tooling),
# Python 3.12 (uv), và cài OpenChamber qua NPM (OpenCode agent cài riêng ở layer
# dưới vì nó không đi qua npm).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git ssh build-essential tini procps unzip psmisc tar \
        chromium fonts-liberation fonts-noto-color-emoji \
    && uv python install 3.12 \
    && ln -sf /root/.local/share/uv/python/cpython-3.12-linux-*/bin/python3.12 /usr/local/bin/python3 \
    && ln -sf /usr/local/bin/python3 /usr/local/bin/python \
    && npm install --global --no-audit --no-fund \
        "@openchamber/web@${OPENCHAMBER_VERSION}" \
    && npm ls -g --depth=0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /root/.npm

# ---------------------------------------------------------------------------
# OpenCode 2.x — AGENT DUY NHẤT mà OpenChamber chấp nhận.
#
# Vì sao không phải `opencode-ai`?:
#   - `opencode-ai` là dòng v1 (latest 1.19.3). OpenCode v2 đổi tên package
#     thành `@opencode/cli` (latest 2.1.2).
#   - OpenChamber >= 2.x HARD-REQUIRE OpenCode >= 2.0.20. Xem upstream
#     server/lib/opencode/compatibility.js:
#         MINIMUM_OPENCODE_VERSION = '2.0.20'
#         isSupportedOpenCodeVersion() yêu cầu major === 2
#     Thiếu v2 thì container vẫn boot, UI vẫn lên, /health vẫn 200 -> image
#     trông healthy nhưng agent chết hoàn toàn:
#         "Failed to start OpenCode: OpenCode 1.19.3 is installed.
#          OpenChamber requires OpenCode 2.0.20 or newer."
#         "Continuing without OpenCode integration..."
#
# Vì sao dùng installer chính thức thay vì `npm install -g @opencode/cli`?:
#   - npm kéo TOÀN BỘ optionalDependencies: cli-linux-x64, -x64-musl,
#     -x64-baseline, -x64-baseline-musl -> 4 bản ~200MB = ~815MB image.
#   - installer chính thức tải đúng 1 tarball theo arch của builder
#     (và tự detect AVX2/musl) -> ~204MB, là file thật, không phải symlink.
#   - Đây cũng chính là cách upstream OpenChamber tự cài v2
#     (server/lib/opencode/v2-install.js -> https://opencode.ai/v2/install).
#
# Binary đặt ở /usr/bin -> nằm trong image layer, KHÔNG nằm trong volume
# ~/.opencode, nên image đi đâu thì agent đi theo đó.
# OPENCODE_BINARY trỏ thẳng vào đó -> upstream resolve đúng binary này bất kể
# thứ tự PATH (thứ tự resolve upstream: OPENCODE_BINARY -> bundled -> PATH ->
# ~/.opencode/bin; nếu để mặc PATH thì binary cũ ở PATH sẽ thắng).
#
# Về env của installer gốc: installer đọc `VERSION` để ghim version, và dùng
# `$HOME` để suy ra thư mục cài (INSTALL_DIR=$HOME/.opencode/bin) - nó KHÔNG có
# env riêng để đổi thư mục. Nên:
#   - HOME=/usr  -> cài vào /usr/.opencode/bin, tức nằm ngoài mọi volume home
#     (nếu để HOME=/root và /root là volume thì installer sẽ ghi vào volume).
#   - VERSION=.. -> ghim version bằng chính env gốc của installer.
# Sau đó chuyển ra /usr/bin và dọn thư mục tạm.
# ---------------------------------------------------------------------------
RUN set -eux; \
    curl -fsSL https://opencode.ai/v2/install -o /tmp/opencode-install.sh; \
    if [ "${OPENCODE_VERSION}" = "latest" ]; then \
        HOME=/usr bash /tmp/opencode-install.sh --no-modify-path; \
    else \
        HOME=/usr VERSION="${OPENCODE_VERSION}" bash /tmp/opencode-install.sh --no-modify-path; \
    fi; \
    rm -f /tmp/opencode-install.sh; \
    mv /usr/.opencode/bin/opencode /usr/bin/opencode; \
    mv /usr/.opencode/bin/opencode2 /usr/bin/opencode2; \
    rm -rf /usr/.opencode; \
    chmod 0755 /usr/bin/opencode /usr/bin/opencode2

# ---------------------------------------------------------------------------
# GUARD: fail lúc BUILD chứ không để container chết âm thầm lúc chạy.
# Đây chính là lớp phòng thủ cho bug "agent v1 chạy được UI nhưng agent chết".
# ---------------------------------------------------------------------------
RUN set -eu; \
    node -e 'const [a,b]=process.versions.node.split(".").map(Number); if(a<24||(a===24&&b<14)){console.error("FATAL: node "+process.versions.node+" < 24.14 (required by @openchamber/web engines)");process.exit(1);} console.log("node "+process.versions.node+" OK");'; \
    node -e 'const v=process.argv[1].replace(/^v/,"").split(".").map(Number); if(v[0]!==2||(v[1]===0&&v[2]<20)){console.error("FATAL: OpenCode "+process.argv[1]+" is unsupported. OpenChamber requires OpenCode >= 2.0.20");process.exit(1);} console.log("OpenCode "+process.argv[1]+" OK");' "$(/usr/bin/opencode --version | awk '{print $2}')"

# Wrapper scripts cho Chromium chạy an toàn trong môi trường container (root / limited /dev/shm)
RUN printf '#!/bin/sh\nexec /usr/bin/chromium --no-sandbox --disable-dev-shm-usage "$@"\n' > /usr/local/bin/chromium \
    && chmod +x /usr/local/bin/chromium \
    && ln -s /usr/local/bin/chromium /usr/local/bin/google-chrome \
    && ln -s /usr/local/bin/chromium /usr/local/bin/chrome

# Entrypoint: foreground + SSH key + OPENCODE_CONFIG_DIR + OH_MY_OPENCODE
COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Metadata cho GHCR
LABEL org.opencontainers.image.title="OpenChamber (community)" \
      org.opencontainers.image.description="OpenChamber web UI + OpenCode agent + Chromium - npm thin image" \
      org.opencontainers.image.source="https://github.com/hung319/openchamber-docker" \
      org.opencontainers.image.version="${OPENCHAMBER_VERSION}" \
      org.openchamber.opencode.version="${OPENCODE_VERSION}"

EXPOSE 8080

# Healthcheck dựa trên endpoint /health của OpenChamber server
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${OPENCHAMBER_PORT}/health" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
