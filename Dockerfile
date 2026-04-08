# syntax=docker/dockerfile:1

# Stage 1: Builder
FROM oven/bun:1-slim AS builder
WORKDIR /app

# Copy các file config để tận dụng cache layer
COPY package.json bun.lock ./
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/desktop/package.json ./packages/desktop/
COPY packages/vscode/package.json ./packages/vscode/

RUN bun install --frozen-lockfile --ignore-scripts

# Copy code và build
COPY . .
RUN bun run build:web

# Stage 2: Runtime (Bản slim có thể dùng apt)
FROM oven/bun:1-slim AS runtime
WORKDIR /home/openchamber

# Cài đặt các công cụ hệ thống cần thiết (Bạn có thể dùng apt thêm sau này nếu cần)
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  git \
  curl \
  nodejs \
  npm \
  openssh-client \
  python3 \
  && rm -rf /var/lib/apt/lists/*

# Cài cloudflared (để fix architecture issue khi chạy đa nền tảng, ta nên tải qua curl thay vì copy cứng 1 mã sha256 của amd64)
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$(dpkg --print-architecture).deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb

# Tạo user để bảo mật (Không chạy quyền root)
RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}
ENV NODE_ENV=production

# Cài opencode-ai ở runtime
RUN npm config set prefix /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.npm-global /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g opencode-ai

# Copy entrypoint và cấp quyền
COPY --chown=openchamber:openchamber scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh
RUN chmod +x /home/openchamber/openchamber-entrypoint.sh

# Copy kết quả từ builder sang
COPY --from=builder --chown=openchamber:openchamber /app/node_modules ./node_modules
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder --chown=openchamber:openchamber /app/package.json ./package.json
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/bin ./packages/web/bin
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/server ./packages/web/server
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/dist ./packages/web/dist

EXPOSE 3000

ENTRYPOINT ["/home/openchamber/openchamber-entrypoint.sh"]
