# OpenChamber Docker (community)

Image Docker "thin" cho [OpenChamber](https://github.com/anomalyco/openchamber) — UI web +
agent [OpenCode](https://opencode.ai) + Chromium, đóng gói từ bản npm chính thức
(`@openchamber/web`), không build từ source.

```bash
docker run -d --name openchamber \
  -p 8080:8080 \
  -v opencode-config:/root/.config/opencode \
  -v opencode-data:/root/.local/share/opencode \
  ghcr.io/hung319/openchamber-docker:latest
```

Mở <http://localhost:8080> — đăng nhập bằng `changeme` (đổi được, xem [Biến môi trường](#biến-môi-trường)).

---

## Mục lục

- [Tags](#tags)
- [Biến môi trường](#biến-môi-trường)
- [Volumes](#volumes)
- [docker compose](#docker-compose)
- [Đăng nhập provider (auth)](#đăng-nhập-provider-auth)
- [SSH key](#ssh-key)
- [Tính năng phụ](#tính-năng-phụ)
- [Build image từ source](#build-image-từ-source)
- [Vì sao binary OpenCode nằm ở /usr/bin](#vì-sao-binary-opencode-nằm-ở-usrbin)
- [Vì sao cần Node 24 và OpenCode v2](#vì-sao-cần-node-24-và-opencode-v2)
- [Troubleshooting](#troubleshooting)

---

## Tags

| Tag | Ý nghĩa |
|---|---|
| `latest` | Bản mới nhất (OpenChamber + OpenCode đều latest) |
| `2.5.0` | Bản OpenChamber cụ thể (multi-arch) |
| `2.5.0-amd64` / `2.5.0-arm64` | Bản cụ thể cho từng kiến trúc |

Image được build tự động 2 lần/ngày bởi [`.github/workflows/main.yml`](.github/workflows/main.yml).
CI resolve version `@openchamber/web` **và** `@opencode/cli` từ npm rồi pin vào build-arg, nên
mỗi lần build đều tái lập được. Image sẽ được rebuild khi **một trong hai** version thay đổi —
nếu chỉ rebuild khi OpenChamber đổi thì người dùng sẽ bị kẹt ở agent cũ.

Version đang build được ghi trong [`latest_npm_version.txt`](latest_npm_version.txt):

```
openchamber=2.5.0
opencode=2.1.2
```

## Biến môi trường

### Bắt buộc nên đặt

| Biến | Mặc định | Ghi chú |
|---|---|---|
| `OPENCHAMBER_UI_PASSWORD` | `changeme` | Mật khẩu đăng nhập UI. **Luôn đặt lại khi expose ra ngoài mạng.** |

> Image bind `0.0.0.0`, mà OpenChamber **từ chối khởi động** nếu không có UI auth
> (exit code 4). Vì vậy image đặt sẵn `changeme` để `docker run` lên được ngay.
> Thứ tự ưu tiên: `OPENCHAMBER_UI_PASSWORD` > `UI_PASSWORD` (alias legacy) > `changeme`.
> Khi đang dùng pass mặc định, log sẽ cảnh báo:
> `[entrypoint] Using DEFAULT UI password 'changeme' - set -e OPENCHAMBER_UI_PASSWORD=... to change it`

### Tuỳ chọn

| Biến | Mặc định | Ghi chú |
|---|---|---|
| `OPENCHAMBER_HOST` | `0.0.0.0` | Bind address |
| `OPENCHAMBER_PORT` | `8080` | Port (cần map `-p` tương ứng) |
| `OPENCHAMBER_LAN_URL` | — | URL để user mở UI từ máy khác (upstream dành riêng cho Docker: container không thấy IP host) |
| `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` | `false` | **Không nên bật** — cho phép bind LAN mà không cần UI auth |
| `OPENCODE_CONFIG_DIR` | `/root/.config/opencode` | Thư mục config OpenCode |
| `OPENCODE_BINARY` | `/usr/bin/opencode` | Đường dẫn binary agent (đã bake sẵn trong image) |
| `OH_MY_OPENCODE` | `false` | Set `true` để cài `oh-my-opencode` lúc boot (cần mạng) |

## Volumes

Nên mount để giữ config, phiên làm việc và đăng nhập:

| Volume | Chứa gì |
|---|---|
| `/root/.config/opencode` | Config OpenCode (`opencode.json`, `cli.json`) |
| `/root/.local/share/opencode` | `auth.json` (token provider), session/message database, snapshot |
| `/root/.config/openchamber` | Setting OpenChamber, chat, git identity, GitHub auth, log |
| `/root/.ssh` | SSH key cho agent (sinh lúc boot nếu chưa có) |

Binary agent **không** nằm trong volume nào — nó được bake thẳng vào `/usr/bin` trong image layer
(xem [giải thích](#vì-sao-binary-opencode-nằm-ở-usrbin)).

## docker compose

```yaml
services:
  openchamber:
    image: ghcr.io/hung319/openchamber-docker:latest
    container_name: openchamber
    ports:
      - "8080:8080"
    environment:
      OPENCHAMBER_UI_PASSWORD: "${OPENCHAMBER_UI_PASSWORD:-changeme}"
      OPENCHAMBER_LAN_URL: "http://192.168.1.10:8080"
    volumes:
      - opencode-config:/root/.config/opencode
      - opencode-data:/root/.local/share/opencode
      - openchamber-config:/root/.config/openchamber
      - openchamber-ssh:/root/.ssh
    restart: unless-stopped

volumes:
  opencode-config:
  opencode-data:
  openchamber-config:
  openchamber-ssh:
```

## Đăng nhập provider (auth)

Agent dùng OpenCode nên credential provider nằm trong `/root/.local/share/opencode/auth.json`.
Có 2 cách:

1. **Trong UI** — mở web UI, vào phần Providers/Integrations, đăng nhập (Anthropic, GitHub Copilot…).
2. **Từ CLI trong container**:

   ```bash
   docker exec -it openchamber opencode auth login
   ```

Volume `/root/.local/share/opencode` giữ token qua các lần restart container.

## SSH key

Container sinh SSH key ed25519 ở `/root/.ssh/id_ed25519` nếu chưa có, và in public key ra log:

```
[entrypoint] SSH public key:
ssh-ed25519 AAAAC3... user@host
```

Copy key đó lên GitHub/GitLab (Settings → SSH keys) để agent pull/push được repo private.

## Tính năng phụ

- **Chromium** có sẵn ở `/usr/local/bin/chromium` (kèm `--no-sandbox --disable-dev-shm-usage`
  cho môi trường container), dùng cho browser/CDP tooling.
- **Python 3.12** qua `uv` ở `/usr/local/bin/python3`.
- **`oh-my-opencode`** (tùy chọn) — set `OH_MY_OPENCODE=true`. Lưu ý package này **không** tạo bin
  tên `opencode`, nên không che binary ở `/usr/bin`.

## Build image từ source

```bash
docker build \
  --build-arg OPENCHAMBER_VERSION=2.5.0 \
  --build-arg OPENCODE_VERSION=2.1.2 \
  -t openchamber-docker:local .
```

Bỏ `--build-arg` thì mặc định là `latest` (tải bản mới nhất lúc build).

Image build sẽ **fail** nếu cặp version sai:

```
FATAL: node 22.23.3 < 24.14 (required by @openchamber/web engines)
FATAL: OpenCode 1.19.3 is unsupported. OpenChamber requires OpenCode >= 2.0.20
```

## Vì sao binary OpenCode nằm ở `/usr/bin`

OpenCode được cài bằng installer chính thức (`https://opencode.ai/v2/install`) — cùng cơ chế
upstream OpenChamber tự dùng:

```dockerfile
HOME=/usr VERSION="${OPENCODE_VERSION}" bash /tmp/opencode-install.sh --no-modify-path
mv /usr/.opencode/bin/opencode  /usr/bin/opencode
mv /usr/.opencode/bin/opencode2 /usr/bin/opencode2
rm -rf /usr/.opencode
```

- Installer **không có** env riêng để đổi thư mục cài — cả bản v1 lẫn v2 đều hardcode
  `INSTALL_DIR=$HOME/.opencode/bin`. Nên mình dùng `HOME=/usr` để thư mục cài nằm ngoài mọi
  volume home, rồi chuyển file ra `/usr/bin` và dọn thư mục tạm.
- `VERSION=` là env gốc của installer, dùng để ghim version thay cho flag `--version`.
- Kết quả là **file thật** nằm trong image layer (204MB), không phải symlink trỏ vào npm tree.
  npm global (`npm i -g @opencode/cli`) sẽ kéo *toàn bộ* optionalDependencies
  (`-x64`, `-x64-musl`, `-x64-baseline`, `-x64-baseline-musl`) → **~815MB** image.
- `OPENCODE_BINARY=/usr/bin/opencode` được set sẵn vì thứ tự resolve của upstream là
  `OPENCODE_BINARY → bundled → PATH → ~/.opencode/bin` — nếu chỉ dựa vào PATH thì một binary cũ
  nằm trước sẽ thắng.

## Vì sao cần Node 24 và OpenCode v2

`@openchamber/web` yêu cầu `engines.node >= 24.14.0`, và OpenChamber **hard-require** OpenCode
`>= 2.0.20` (upstream `server/lib/opencode/compatibility.js`):

```js
MINIMUM_OPENCODE_VERSION = '2.0.20'
// major phải === 2
```

Image cũ cài `opencode-ai` — đó là dòng **v1** (latest `1.19.3`), dù package của v2 là
`@opencode/cli`. Hậu quả là container vẫn boot, UI vẫn lên, `/health` vẫn 200, nhưng **agent
chết hoàn toàn**:

```
Failed to start OpenCode: OpenCode 1.19.3 is installed. OpenChamber requires OpenCode 2.0.20 or newer.
Continuing without OpenCode integration...
```

Vì vậy image giờ có **guard lúc build** — fail ngay khi build thay vì để container chết âm thầm
lúc chạy.

## Troubleshooting

**UI lên nhưng agent không phản hồi**
Xem log có `Detected OpenCode port: <port>` không. Nếu không, đọc dòng
`Failed to start OpenCode` — thường là binary v1 hoặc thiếu bản `>= 2.0.20`.
Kiểm tra nhanh:

```bash
docker exec openchamber opencode --version   # phải >= 2.0.20
docker exec openchamber /usr/bin/opencode --version
```

**Container exit code 4 ngay khi start**
Thiếu UI password khi bind `0.0.0.0`. Đặt `OPENCHAMBER_UI_PASSWORD`, hoặc chấp nhận rủi ro với
`OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` (không khuyến nghị).

**Agent không pull/push được private repo**
Copy SSH key từ log container vào GitHub/GitLab, và mount `/root/.ssh` để giữ key giữa các lần
restart.

**Muốn xem version agent đang chạy**

```bash
docker logs openchamber 2>&1 | grep OpenCode
# [entrypoint] OpenCode: opencode v2.1.2 (/usr/bin/opencode)
```

---

Repo này là image community, không phải upstream chính thức.
Upstream: <https://github.com/anomalyco/openchamber>
