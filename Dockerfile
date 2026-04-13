FROM debian:stable-slim

# Copy uv package manager (Dùng để cài python gọn nhất)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Khai báo môi trường tập trung
ENV PATH="/usr/local/bin:/usr/bin:${PATH}" \
    OPENCHAMBER_PORT=8080 \
    OPENCHAMBER_HOST=0.0.0.0 \
    NODE_ENV=production

WORKDIR /root

# Khai báo biến lúc build để apt không hỏi các cấu hình linh tinh
ARG DEBIAN_FRONTEND=noninteractive

# GOM LAYER: Cài hệ thống, Nodejs+NPM (từ repo debian), Python, và cài OpenChamber qua NPM
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git ssh build-essential tini procps unzip psmisc \
        nodejs npm \
    && uv python install 3.12 \
    && npm install -g opencode-ai@latest @openchamber/web@latest \
    && npm cache clean --force \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Cấu hình wrapper script cho opencode
RUN mv /usr/local/bin/opencode /usr/local/bin/opencode-original \
    && echo -e '#!/bin/bash\nrm -rf /root/.cache/opencode/package.json 2>/dev/null || true\nexec /usr/local/bin/opencode-original "$@"' > /usr/local/bin/opencode \
    && chmod +x /usr/local/bin/opencode

# Cập nhật Entrypoint: Ép chạy Foreground, bỏ chế độ chạy ngầm
RUN cat <<'EOF' > /usr/local/bin/entrypoint && chmod +x /usr/local/bin/entrypoint
#!/bin/bash
set -e

# Chạy trực tiếp tiến trình chính bằng exec kết hợp cờ --foreground
exec openchamber serve \
    --port "${OPENCHAMBER_PORT}" \
    --host "${OPENCHAMBER_HOST}" \
    --foreground \
    ${OPENCHAMBER_UI_PASSWORD:+--ui-password "$OPENCHAMBER_UI_PASSWORD"}
EOF

EXPOSE 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
