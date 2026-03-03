---
name: Docker Deployment Guide
description: 通用 Docker/Docker Compose 部署参考：Dockerfile 最佳实践、npm/pip 国内镜像、大文件上传、Nginx 反代、常见坑点。适用于 Flask+Vite、Node.js、Python 等各类 Web 项目的容器化部署。
---

# Docker 部署通用指南

适用于将 Web 项目（尤其是前后端分离架构）容器化部署到 Linux 服务器的完整参考。

---

## 一、Dockerfile 编写原则

### 1.1 依赖层与代码层必须分离（最重要）

利用 Docker 层缓存的关键：**只有 `package.json` / `requirements.txt` 变化时才重装依赖。**

```dockerfile
# ✅ 正确：先只复制依赖文件，安装依赖，再复制源码
COPY package.json package-lock.json ./
RUN npm ci
COPY src/ ./src/

# ❌ 错误：源码改动会导致 npm ci 每次重跑
COPY . .
RUN npm ci
```

Python 同理：
```dockerfile
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
```

### 1.2 多阶段构建（前端必用）

将"构建环境"和"运行环境"分离，最终镜像只包含运行所需文件，体积极小。

```dockerfile
# Stage 1: 构建
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json .npmrc ./
RUN npm ci --ignore-scripts
COPY . .
RUN npm run build

# Stage 2: 运行（只取 dist/，不含 node_modules）
FROM nginx:1.27-alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/app.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### 1.3 Alpine vs Slim 的选择

| 基础镜像 | 体积 | 适用场景 |
|---------|------|---------|
| `node:20-alpine` | 最小 | 纯 JS/TS，无原生 module 依赖 |
| `node:20-slim` | 中等 | 有原生依赖（如 Prisma、bcrypt）时用 slim |
| `python:3.12-slim` | 中等 | Python 应用标准选择 |
| `nginx:1.27-alpine` | 极小 | 纯静态文件托管 |

---

## 二、国内网络：镜像源配置

### 2.1 npm（`.npmrc`）

```ini
registry=https://registry.npmmirror.com
fetch-retries=3
fetch-retry-mintimeout=10000
fetch-retry-maxtimeout=60000
fetch-timeout=120000
prefer-offline=false   # ⚠️ Docker 环境必须为 false，见下方 CAUTION
```

> [!CAUTION]
> **`prefer-offline=true` 是 Docker 构建卡死 / npm install 挂起的常见根因。**
> Docker 容器内无本地 npm 缓存，该选项会让每个包都等满 `fetch-timeout`（默认 2 分钟）
> 才超时，大量包叠加后表现为构建"卡死"。**务必保持 `prefer-offline=false`。**

Dockerfile 中优先使用 `npm ci` 而非 `npm install`：
- `npm ci`：严格按 lockfile 安装，速度更快，行为可预测，适合 CI/Docker
- `npm install`：会更新 lockfile，不适合 Docker 构建环境

> [!CAUTION]
> **`npm ci` 要求 `package-lock.json` 必须预先存在于代码仓库中。**
> 在第一次 Docker 构建前，须在宿主机执行 `npm install` 生成 lockfile 并提交到 Git，
> 否则构建会报错：`npm ci can only install with an existing package-lock.json`。
> Dockerfile 中 `COPY` 时也必须显式包含该文件：
> ```dockerfile
> COPY package.json package-lock.json .npmrc ./
> RUN npm ci
> ```

### 2.2 pip（Python）

```dockerfile
RUN pip install --no-cache-dir \
    -i https://pypi.tuna.tsinghua.edu.cn/simple \
    -r requirements.txt
```

常用镜像源：
- 清华：`https://pypi.tuna.tsinghua.edu.cn/simple`
- 阿里云：`https://mirrors.aliyun.com/pypi/simple`

### 2.3 apt（Debian/Ubuntu 系基础镜像）

```dockerfile
# Debian bookworm (node:slim, python:slim 等)
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
```

```dockerfile
# Alpine
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
    && apk add --no-cache curl
```

---

## 三、Nginx 反代配置（前后端分离）

前端 Nginx 作统一入口，`/api/` 流量通过内网转发给后端，无需配置 CORS。

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # ── 静态资源（强缓存）
    location ~* \.(js|css|woff2?|svg|png|jpg|ico|webp)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # ── API 反代
    location /api/ {
        proxy_pass         http://backend:8000;   # 使用 compose 服务名
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;

        # 大文件上传/下载必须调大超时
        proxy_read_timeout    3600s;
        proxy_send_timeout    3600s;
        client_body_timeout   3600s;

        # 大文件必须关闭缓冲
        proxy_buffering         off;
        proxy_request_buffering off;
    }

    # ── SPA fallback（Vue/React 路由必须）
    location / {
        try_files $uri $uri/ /index.html;
    }

    # ── 上传大小限制（按需调整）
    client_max_body_size 2g;

    gzip on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;
}
```

> [!IMPORTANT]
> `proxy_pass` 的主机名使用 **Docker Compose 服务名**（如 `backend`），
> 不要写 IP，Docker 内置 DNS 会自动解析。

---

## 四、docker-compose.yml 编排

> [!CAUTION]
> 不要在 `docker-compose.yml` 顶层加 `version: '3.9'` 等字段。
> Docker Compose V2 已正式废弃该字段，会输出 warning。直接从 `services:` 开始即可。

```yaml
services:
  backend:
    build:
      context: ./apps/backend
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./data:/app/data        # 数据持久化
      - ./logs:/app/logs        # 日志持久化
    expose:
      - "8000"                  # 只暴露内网，不对外
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8000/health"]
      interval: 15s
      timeout: 5s
      start_period: 30s
      retries: 3

  frontend:
    build:
      context: ./apps/frontend
    ports:
      - "${FRONTEND_PORT:-80}:80"
    depends_on:
      backend:
        condition: service_healthy   # 等后端健康检查通过
    networks:
      - app_net

networks:
  app_net:
    driver: bridge
```

> [!IMPORTANT]
> `depends_on: condition: service_healthy` 必须配合后端的 `healthcheck` 配置一同使用，
> 否则 Docker Compose 会报错。健康检查接口（`/health` 或任意轻量 API）必须存在。

---

## 五、.dockerignore

```gitignore
# 依赖
node_modules/
dist/
.vite/
.nuxt/
.output/
__pycache__/
*.py[cod]
venv/
.venv/

# 数据与日志（运行时产生，不进镜像）
data/
logs/
*.db
*.sqlite3

# 环境变量（安全，绝对不进镜像）
.env
.env.*
!.env.example

# Git & IDE
.git/
.gitignore
.vscode/
.idea/
.DS_Store

# 文档（可选）
README.md
docs/
```

> [!IMPORTANT]
> `.dockerignore` 放在 **build context 目录**下（即 `docker-compose.yml` 中
> `context:` 指定的目录），而不是项目根目录（除非 context 就是根目录）。

---

## 六、常见问题速查

| 问题现象 | 根因 | 解决方案 |
|---------|------|---------|
| `npm install` / `npm ci` 卡死 | `.npmrc` 的 `prefer-offline=true` | 改为 `prefer-offline=false` |
| pip install 超时 | 默认连 pypi.org，国内慢 | 加 `-i https://pypi.tuna.tsinghua.edu.cn/simple` |
| apt-get update 超时 | 默认源在国外 | 替换为阿里云镜像 |
| 大文件上传失败/超时 | Nginx 默认 60s 超时、1MB 上限 | `proxy_read_timeout 3600s` + `client_max_body_size 2g` |
| 前端启动时后端未就绪 | `depends_on` 仅控制顺序 | `condition: service_healthy` + 后端加 `healthcheck` |
| 代码改动后依赖重装 | `COPY . .` 在 `npm ci` 前 | 先 `COPY package*.json ./`，`npm ci` 后再 `COPY . .` |
| 环境变量泄漏进镜像 | `.env` 未加入 `.dockerignore` | `.dockerignore` 加 `.env` |
| 容器重启后数据丢失 | 未配置 volume | `volumes: ./data:/app/data` |
| Nginx `/api/` 返回 404 | 反代配置错误或 location 尾部斜线 | 检查 `proxy_pass` 与 `location` 尾斜线是否一致 |
| gunicorn worker 超时 | 默认 timeout 30s | `--timeout 3600` |

---

## 七、部署命令参考

```bash
# 首次构建并启动
docker compose up --build -d

# 查看服务状态
docker compose ps

# 查看日志（实时）
docker compose logs -f
docker compose logs backend --tail=100

# 仅重建单个服务
docker compose up --build -d backend

# 停止
docker compose down

# 停止并完全清理（含 volume，慎用！）
docker compose down -v --rmi all
```
