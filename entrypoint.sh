#!/bin/bash
set -euo pipefail

# ============================================================================
# OpenChamber entrypoint (community image)
# - Chạy server foreground qua exec -> tini nhận SIGTERM, tiến trình chính
#   là PID 1 -> shutdown sạch sẽ (pattern tốt hơn daemon+logs của upstream)
# - Sinh SSH key nếu chưa có (agent cần cho git/ssh operations)
# - Đảm bảo OPENCODE_CONFIG_DIR được set (khớp volume ~/.config/opencode)
# - Tương thích OH_MY_OPENCODE và UI_PASSWORD alias từ upstream
# ============================================================================

export OPENCHAMBER_HOST="${OPENCHAMBER_HOST:-0.0.0.0}"
export OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-8080}"
export OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

# OpenCode agent: binary được bake vào /usr/bin (nằm trong image layer, KHÔNG
# nằm trong volume ~/.opencode) nên image đi đâu thì agent đi theo đó.
# OPENCODE_BINARY trỏ thẳng vào đó: thứ tự resolve của upstream là
# OPENCODE_BINARY -> bundled -> PATH -> ~/.opencode/bin, nên nếu chỉ dựa vào
# PATH thì một binary cũ nằm trước trong PATH sẽ thắng.
export OPENCODE_BINARY="${OPENCODE_BINARY:-/usr/bin/opencode}"

# UI password: hỗ trợ cả OPENCHAMBER_UI_PASSWORD và legacy UI_PASSWORD (tương thích upstream)
if [ -z "${OPENCHAMBER_UI_PASSWORD:-}" ] && [ -n "${UI_PASSWORD:-}" ]; then
    OPENCHAMBER_UI_PASSWORD="$UI_PASSWORD"
    export OPENCHAMBER_UI_PASSWORD
fi

# Pass mặc định: image bind 0.0.0.0 nên OpenChamber BẮT BUỘC phải có UI
# password, nếu không server từ chối khởi động (exit code 4):
#   "OpenChamber refuses to bind to 0.0.0.0 without UI authentication."
# -> đặt sẵn một pass để `docker run` không cần config gì cũng lên được.
# Thứ tự ưu tiên: OPENCHAMBER_UI_PASSWORD > UI_PASSWORD (legacy) > mặc định.
# Lưu ý: default nằm ở runtime (không phải ENV của image) để không chặn
# nhánh legacy UI_PASSWORD ở trên.
DEFAULT_UI_PASSWORD="changeme"
if [ -z "${OPENCHAMBER_UI_PASSWORD:-}" ]; then
    OPENCHAMBER_UI_PASSWORD="$DEFAULT_UI_PASSWORD"
    export OPENCHAMBER_UI_PASSWORD
    echo "[entrypoint] Using DEFAULT UI password '$DEFAULT_UI_PASSWORD' - set -e OPENCHAMBER_UI_PASSWORD=... to change it"
fi

# SSH key cho các thao tác git/ssh của agent (lần đầu boot sẽ tự sinh)
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh" 2>/dev/null || true
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "[entrypoint] Generating SSH key..."
    ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
fi
chmod 600 "$HOME/.ssh/id_ed25519" 2>/dev/null || true
chmod 644 "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true

# In SSH public key ra log để dễ dàng copy vào GitHub/GitLab
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    echo "[entrypoint] SSH public key:"
    cat "$HOME/.ssh/id_ed25519.pub"
fi

# LƯU Ý (core opencode v2): KHÔNG xoá cache mỗi boot nữa. Từ core v2 layout cache
# plugin là ~/.cache/opencode/npm/<pkg>@<spec>/<generation>/, tự re-resolve tag
# (@latest...) và có GC riêng (giữ 2 generation gần nhất, xoá mục cũ >7 ngày).
# Xoá gì thêm mỗi boot chỉ làm plugin re-download lại từ đầu, vô ích.
# (Đường cũ ~/.cache/opencode/package.json chỉ còn ở core v1.x - đã bỏ.)

# Tích hợp OH_MY_OPENCODE nếu người dùng bật biến môi trường
if [ "${OH_MY_OPENCODE:-false}" = "true" ]; then
    OMO_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/oh-my-opencode.json"
    if [ ! -f "${OMO_CONFIG_FILE}" ]; then
        echo "[entrypoint] Installing oh-my-opencode..."
        npm install -g --no-audit --no-fund oh-my-opencode
        OMO_INSTALL_ARGS="--no-tui --claude=no --openai=no --gemini=no --copilot=no --opencode-zen=no --zai-coding-plan=no --kimi-for-coding=no --skip-auth"
        oh-my-opencode install ${OMO_INSTALL_ARGS} || echo "[entrypoint] oh-my-opencode setup had warnings, continuing"
    fi
fi

# Nếu người dùng truyền custom command thì exec command đó
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# Log version agent để debug nhanh: OpenChamber hard-require OpenCode >= 2.0.20,
# thiếu bản đó thì UI lên được nhưng agent chết (log "Continuing without
# OpenCode integration...").
if [ -x "$OPENCODE_BINARY" ]; then
    echo "[entrypoint] OpenCode: $("$OPENCODE_BINARY" --version 2>/dev/null || echo unknown) ($OPENCODE_BINARY)"
else
    echo "[entrypoint] WARNING: OpenCode binary not found at $OPENCODE_BINARY - agent features will not work"
fi

# Chạy server trực tiếp ở foreground
args=(serve \
    --port "${OPENCHAMBER_PORT}" \
    --host "${OPENCHAMBER_HOST}" \
    --foreground)
if [ -n "${OPENCHAMBER_UI_PASSWORD:-}" ]; then
    args+=(--ui-password "${OPENCHAMBER_UI_PASSWORD}")
fi

exec openchamber "${args[@]}"
