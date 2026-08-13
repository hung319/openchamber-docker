#!/bin/bash
set -euo pipefail

# ============================================================================
# OpenChamber entrypoint (community image)
# - Chạy server foreground qua exec -> tini nhận SIGTERM, tiến trình chính
#   là PID 1 -> shutdown sạch sẽ (pattern tốt hơn daemon+logs của upstream)
# - Sinh SSH key nếu chưa có (agent cần cho git/ssh operations)
# - Đảm bảo OPENCODE_CONFIG_DIR được set (khớp volume ~/.config/opencode)
# ============================================================================

export OPENCHAMBER_HOST="${OPENCHAMBER_HOST:-0.0.0.0}"
export OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-8080}"
export OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

# SSH key cho các thao tác git/ssh của agent (lần đầu boot sẽ tự sinh)
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
fi

# Xoá cache package.json của opencode mỗi lần boot để opencode resolve đúng
# version đã cài trong image (tránh cache stale khi volume /root/.cache/opencode
# tồn tại qua các lần upgrade image)
rm -rf "$HOME/.cache/opencode/package.json" 2>/dev/null || true

# Chạy server trực tiếp ở foreground
args=(serve \
    --port "${OPENCHAMBER_PORT}" \
    --host "${OPENCHAMBER_HOST}" \
    --foreground)
if [ -n "${OPENCHAMBER_UI_PASSWORD:-}" ]; then
    args+=(--ui-password "${OPENCHAMBER_UI_PASSWORD}")
fi

exec openchamber "${args[@]}"
