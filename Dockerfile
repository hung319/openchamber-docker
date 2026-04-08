# syntax=docker/dockerfile:1

# ==========================================
# Stage 1: Builder
# ==========================================
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

# ==========================================
# Stage 2: Runtime 
# ==========================================
FROM oven/bun:1-slim AS runtime
WORKDIR /home/openchamber

# Gộp chung: Cài APT + Cài Cloudflared + Tạo User vào 1 Layer duy nhất để tối ưu size
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates git curl nodejs npm openssh-client python3 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$(dpkg --print-architecture).deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb \
    && userdel bun \
    && groupadd -g 1000 openchamber \
    && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
    && chown -R openchamber:openchamber /home/openchamber

# Đổi sang user non-root
USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}
ENV NODE_ENV=production

# Cài opencode-ai và XÓA CACHE NPM ngay trong cùng 1 lệnh
RUN mkdir -p /home/openchamber/.npm-global /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh \
    && npm config set prefix /home/openchamber/.npm-global \
    && npm install -g opencode-ai \
    && npm cache clean --force

# Dùng --chmod=755 ngay trong COPY để không sinh thêm layer rác
COPY --chmod=755 --chown=openchamber:openchamber scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

# Copy kết quả từ builder sang (giữ nguyên, vì cấu trúc folder khác nhau)
COPY --from=builder --chown=openchamber:openchamber /app/node_modules ./node_modules
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder --chown=openchamber:openchamber /app/package.json ./package.json
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/bin ./packages/web/bin
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/server ./packages/web/server
COPY --from=builder --chown=openchamber:openchamber /app/packages/web/dist ./packages/web/dist

EXPOSE 3000

ENTRYPOINT ["/home/openchamber/openchamber-entrypoint.sh"]
