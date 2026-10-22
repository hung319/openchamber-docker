# OpenChamber Docker (community)

**[English](#en) · [Tiếng Việt](#vi)**

Thin Docker image for [OpenChamber](https://github.com/anomalyco/openchamber) — web UI +
[OpenCode](https://opencode.ai) agent + Chromium, packaged from the official npm release
(`@openchamber/web`), no source build.

> This README is bilingual. Jump to: [English](#en) | [Tiếng Việt](#vi)

---

<a id="en"></a>

# English

## Table of contents

- [Quick start](#en-quick-start)
- [Tags](#en-tags)
- [Environment variables](#en-env)
- [Volumes](#en-volumes)
- [docker compose](#en-compose)
- [Provider authentication](#en-auth)
- [SSH key](#en-ssh)
- [Extras](#en-extras)
- [Building from source](#en-build)
- [Why the OpenCode binary lives in /usr/bin](#en-why-usrbin)
- [Why Node 24 and OpenCode v2 are required](#en-why-node24)
- [Troubleshooting](#en-troubleshooting)

---

## Quick start

<a id="en-quick-start"></a>

```bash
docker run -d --name openchamber \
  -p 8080:8080 \
  -v openchamber-config:/root/.config/openchamber \
  -v opencode-config:/root/.config/opencode \
  -v opencode-data:/root/.local/share/opencode \
  -v openchamber-ssh:/root/.ssh \
  ghcr.io/hung319/openchamber-docker:latest
```

Open <http://localhost:8080> and log in with `changeme` (the image default — change it, see
[UI password](#en-env)).

Add `-e OPENCHAMBER_UI_PASSWORD=...` to set your own password, and always replace the default
before exposing the container outside your machine.

---

## Tags

<a id="en-tags"></a>

| Tag | Meaning |
|---|---|
| `latest` | Latest release (OpenChamber + OpenCode both latest) |
| `2.5.0` | Specific OpenChamber release (multi-arch) |
| `2.5.0-amd64` / `2.5.0-arm64` | Per-architecture builds |

The image is built automatically twice a day by [`.github/workflows/main.yml`](.github/workflows/main.yml).
CI resolves the versions of `@openchamber/web` **and** `@opencode/cli` from npm and pins them as
build args, so every build is reproducible. The image is rebuilt when **either** version changes —
rebuilding only on OpenChamber updates would leave users stuck on an old agent.

The versions currently built are recorded in [`latest_npm_version.txt`](latest_npm_version.txt):

```
openchamber=2.5.0
opencode=2.1.2
```

---

## Environment variables

<a id="en-env"></a>

### You should set this

| Variable | Default | Notes |
|---|---|---|
| `OPENCHAMBER_UI_PASSWORD` | `changeme` | Web UI login password. **Always change it when exposing the container.** |

> The image binds `0.0.0.0`, and OpenChamber **refuses to start** without UI authentication
> (exit code 4). That is why the image ships a default `changeme`, so a plain `docker run` works
> out of the box. Precedence: `OPENCHAMBER_UI_PASSWORD` > `UI_PASSWORD` (legacy alias) > `changeme`.
> While the default is in use the log shows a warning:
> `[entrypoint] Using DEFAULT UI password 'changeme' - set -e OPENCHAMBER_UI_PASSWORD=... to change it`

### Optional

| Variable | Default | Notes |
|---|---|---|
| `OPENCHAMBER_HOST` | `0.0.0.0` | Bind address |
| `OPENCHAMBER_PORT` | `8080` | HTTP port (map with `-p` accordingly) |
| `OPENCHAMBER_LAN_URL` | — | URL users open to reach the UI from another machine (upstream ships this for Docker: a container cannot see the host IP) |
| `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` | `false` | **Not recommended** — allows binding to the LAN with no UI auth |
| `OPENCODE_CONFIG_DIR` | `/root/.config/opencode` | OpenCode config directory |
| `OPENCODE_BINARY` | `/usr/bin/opencode` | Path to the OpenCode agent binary (already baked into the image) |
| `OH_MY_OPENCODE` | `false` | Set `true` to install `oh-my-opencode` at boot (needs network) |

### UI password

The default `changeme` is applied at **runtime** (in `entrypoint.sh`), not as an image `ENV` — an
`ENV` would shadow the legacy `UI_PASSWORD` alias and break it.

---

## Volumes

<a id="en-volumes"></a>

Mount these to keep configuration, sessions and logins:

| Path | Contents |
|---|---|
| `/root/.config/opencode` | OpenCode config (`opencode.json`, `cli.json`) |
| `/root/.local/share/opencode` | `auth.json` (provider tokens), session/message database, snapshots |
| `/root/.config/openchamber` | OpenChamber settings, chats, git identities, GitHub auth, logs |
| `/root/.ssh` | SSH key for the agent (generated at boot if missing) |

The agent binary itself is in **no** volume — it is baked straight into `/usr/bin` in the image
layer (see [why](#en-why-usrbin)).

---

## docker compose

<a id="en-compose"></a>

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

---

## Provider authentication

<a id="en-auth"></a>

The agent is OpenCode, so provider credentials live in `/root/.local/share/opencode/auth.json`.
Two ways to set them up:

1. **From the UI** — open the web UI, go to Providers/Integrations and sign in (Anthropic,
   GitHub Copilot, …).
2. **From the CLI inside the container**:

   ```bash
   docker exec -it openchamber opencode auth login
   ```

Mounting `/root/.local/share/opencode` keeps the tokens across container restarts.

---

## SSH key

<a id="en-ssh"></a>

The container generates an ed25519 SSH key at `/root/.ssh/id_ed25519` if none exists, and prints
the public key to the log:

```
[entrypoint] SSH public key:
ssh-ed25519 AAAAC3... user@host
```

Copy that key into GitHub/GitLab (Settings → SSH keys) so the agent can pull and push private
repositories.

---

## Extras

<a id="en-extras"></a>

- **Chromium** ships at `/usr/local/bin/chromium` (wrapped with `--no-sandbox
  --disable-dev-shm-usage` for containers), used for browser/CDP tooling.
- **Python 3.12** installed via `uv` at `/usr/local/bin/python3`.
- **`oh-my-opencode`** (optional) — set `OH_MY_OPENCODE=true`. Note that this package does **not**
  install a binary named `opencode`, so it never shadows the one in `/usr/bin`.

---

## Building from source

<a id="en-build"></a>

```bash
docker build \
  --build-arg OPENCHAMBER_VERSION=2.5.0 \
  --build-arg OPENCODE_VERSION=2.1.2 \
  -t openchamber-docker:local .
```

Omitting the build args defaults to `latest` (fetches the newest release at build time).

The build **fails** if the version pairing is wrong:

```
FATAL: node 22.23.3 < 24.14 (required by @openchamber/web engines)
FATAL: OpenCode 1.19.3 is unsupported. OpenChamber requires OpenCode >= 2.0.20
```

---

## Why the OpenCode binary lives in /usr/bin

<a id="en-why-usrbin"></a>

OpenCode is installed with the official installer (`https://opencode.ai/v2/install`) — the same
mechanism upstream OpenChamber uses:

```dockerfile
HOME=/usr VERSION="${OPENCODE_VERSION}" bash /tmp/opencode-install.sh --no-modify-path
mv /usr/.opencode/bin/opencode  /usr/bin/opencode
mv /usr/.opencode/bin/opencode2 /usr/bin/opencode2
rm -rf /usr/.opencode
```

- The installer has **no** env var to change the install folder — both v1 and v2 hardcode
  `INSTALL_DIR=$HOME/.opencode/bin`. So `HOME=/usr` is used to keep the install out of any home
  volume, then the file is moved to `/usr/bin` and the temporary directory removed.
- `VERSION=` is the installer's own env var, used to pin the version instead of `--version`.
- The result is a **real file** in the image layer (204MB), not a symlink into an npm tree.
  A global npm install (`npm i -g @opencode/cli`) pulls *all* optionalDependencies
  (`-x64`, `-x64-musl`, `-x64-baseline`, `-x64-baseline-musl`) → **~815MB** image.
- `OPENCODE_BINARY=/usr/bin/opencode` is set because upstream resolves binaries in the order
  `OPENCODE_BINARY → bundled → PATH → ~/.opencode/bin` — relying on `PATH` alone lets a stale
  binary that comes first in `PATH` win.

---

## Why Node 24 and OpenCode v2 are required

<a id="en-why-node24"></a>

`@openchamber/web` requires `engines.node >= 24.14.0`, and OpenChamber **hard-requires** OpenCode
`>= 2.0.20` (upstream `server/lib/opencode/compatibility.js`):

```js
MINIMUM_OPENCODE_VERSION = '2.0.20'
// major must === 2
```

The old image installed `opencode-ai` — that is the **v1** line (latest `1.19.3`), while v2 is
published as `@opencode/cli`. The result was a container that still booted, still served the UI and
still answered `/health` with 200 — while the **agent was completely dead**:

```
Failed to start OpenCode: OpenCode 1.19.3 is installed.
OpenChamber requires OpenCode 2.0.20 or newer.
Continuing without OpenCode integration...
```

That is why the image now has a **build-time guard** — it fails the build instead of letting the
container die silently at runtime.

---

## Troubleshooting

<a id="en-troubleshooting"></a>

**The UI loads but the agent does not respond**
Look for `Detected OpenCode port: <port>` in the logs. If it is missing, read the
`Failed to start OpenCode` line — usually an old v1 binary or a missing `>= 2.0.20` release.
Quick checks:

```bash
docker exec openchamber opencode --version        # must be >= 2.0.20
docker exec openchamber /usr/bin/opencode --version
```

**The container exits with code 4 immediately at start**
Missing UI password while binding `0.0.0.0`. Set `OPENCHAMBER_UI_PASSWORD`, or accept the risk
with `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` (not recommended).

**The agent cannot pull/push private repositories**
Copy the SSH key from the container log into GitHub/GitLab, and mount `/root/.ssh` so the key
survives restarts.

**Check which agent version is running**

```bash
docker logs openchamber 2>&1 | grep OpenCode
# [entrypoint] OpenCode: opencode v2.1.2 (/usr/bin/opencode)
```

---

## License

Follows the license of the upstream project
[anomalyco/openchamber](https://github.com/anomalyco/openchamber).

---

This repository is a community image, not the official upstream one.
Upstream: <https://github.com/anomalyco/openchamber>

---
<a id="vi"></a>

# Tiếng Việt

## Mục lục

- [Quick start](#vi-quick-start)
- [Tags](#vi-tags)
- [Biến môi trường](#vi-env)
- [Volumes](#vi-volumes)
- [docker compose](#vi-compose)
- [Đăng nhập provider (auth)](#vi-auth)
- [SSH key](#vi-ssh)
- [Tính năng phụ](#vi-extras)
- [Build image từ source](#vi-build)
- [Vì sao binary OpenCode nằm ở /usr/bin](#vi-why-usrbin)
- [Vì sao cần Node 24 và OpenCode v2](#vi-why-node24)
- [Troubleshooting](#vi-troubleshooting)

---

## Quick start

<a id="vi-quick-start"></a>

```bash
docker run -d --name openchamber \
  -p 8080:8080 \
  -v openchamber-config:/root/.config/openchamber \
  -v opencode-config:/root/.config/opencode \
  -v opencode-data:/root/.local/share/opencode \
  -v openchamber-ssh:/root/.ssh \
  ghcr.io/hung319/openchamber-docker:latest
```

Mở <http://localhost:8080> — đăng nhập bằng `changeme` (pass mặc định của image; đổi được, xem
[UI password](#vi-env)).

Thêm `-e OPENCHAMBER_UI_PASSWORD=...` nếu muốn đặt pass riêng, và nhớ đổi pass mặc định trước khi
expose ra ngoài mạng.

---

## Tags

<a id="vi-tags"></a>

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

---

## Biến môi trường

<a id="vi-env"></a>

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

### UI password

Default `changeme` được đặt **ở runtime** (trong `entrypoint.sh`), không phải `ENV` của image — nếu
đặt trong `ENV` thì nhánh alias legacy `UI_PASSWORD` sẽ bị chặn chết.

---

## Volumes

<a id="vi-volumes"></a>

Nên mount để giữ config, phiên làm việc và đăng nhập:

| Volume | Chứa gì |
|---|---|
| `/root/.config/opencode` | Config OpenCode (`opencode.json`, `cli.json`) |
| `/root/.local/share/opencode` | `auth.json` (token provider), session/message database, snapshot |
| `/root/.config/openchamber` | Setting OpenChamber, chat, git identity, GitHub auth, log |
| `/root/.ssh` | SSH key cho agent (sinh lúc boot nếu chưa có) |

Binary agent **không** nằm trong volume nào — nó được bake thẳng vào `/usr/bin` trong image layer
(xem [giải thích](#vi-why-usrbin)).

---

## docker compose

<a id="vi-compose"></a>

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

---

## Đăng nhập provider (auth)

<a id="vi-auth"></a>

Agent dùng OpenCode nên credential provider nằm trong `/root/.local/share/opencode/auth.json`.
Có 2 cách:

1. **Trong UI** — mở web UI, vào phần Providers/Integrations, đăng nhập (Anthropic, GitHub Copilot…).
2. **Từ CLI trong container**:

   ```bash
   docker exec -it openchamber opencode auth login
   ```

Volume `/root/.local/share/opencode` giữ token qua các lần restart container.

---

## SSH key

<a id="vi-ssh"></a>

Container sinh SSH key ed25519 ở `/root/.ssh/id_ed25519` nếu chưa có, và in public key ra log:

```
[entrypoint] SSH public key:
ssh-ed25519 AAAAC3... user@host
```

Copy key đó lên GitHub/GitLab (Settings → SSH keys) để agent pull/push được repo private.

---

## Tính năng phụ

<a id="vi-extras"></a>

- **Chromium** có sẵn ở `/usr/local/bin/chromium` (kèm `--no-sandbox --disable-dev-shm-usage`
  cho môi trường container), dùng cho browser/CDP tooling.
- **Python 3.12** qua `uv` ở `/usr/local/bin/python3`.
- **`oh-my-opencode`** (tùy chọn) — set `OH_MY_OPENCODE=true`. Lưu ý package này **không** tạo bin
  tên `opencode`, nên không che binary ở `/usr/bin`.

---

## Build image từ source

<a id="vi-build"></a>

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

---

## Vì sao binary OpenCode nằm ở `/usr/bin`

<a id="vi-why-usrbin"></a>

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

---

## Vì sao cần Node 24 và OpenCode v2

<a id="vi-why-node24"></a>

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

---

## Troubleshooting

<a id="vi-troubleshooting"></a>

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

## License

Theo license của project upstream [anomalyco/openchamber](https://github.com/anomalyco/openchamber).
