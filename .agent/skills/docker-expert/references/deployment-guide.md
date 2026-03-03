# Docker 项目部署通用模板 (Reference)

此文档作为项目容器化的标准模板。请根据实际技术栈（{{STACK}}）替换相应部分。

---

## 一、Dockerfile 核心模板

### 1.1 依赖与生产分离（最佳实践）

```dockerfile
# 选择基础镜像: node:{{VERSION}}-alpine / python:{{VERSION}}-slim
FROM {{BASE_IMAGE}} AS builder

WORKDIR /app

# ✅ 仅复制依赖清单以利用缓存
COPY {{DEP_FILE_1}} {{DEP_FILE_2}} ./
{{INSTALL_COMMAND}}

# 复制源码并构建
COPY . .
{{BUILD_COMMAND}}

# --- 运行阶段 ---
FROM {{RUN_IMAGE}}
{{RUN_SETUP}}
COPY --from=builder /app/{{BUILD_OUTPUT}} {{RUN_DEST}}

EXPOSE {{INTERNAL_PORT}}
{{START_COMMAND}}
```

---

## 二、国内镜像加速配置

### 2.1 包管理器镜像源

| 工具 | 配置文件/命令 | 推荐镜像源 |
|------|--------------|-----------|
| **npm** | `.npmrc` | `registry=https://registry.npmmirror.com` |
| **pip** | `pip install` | `-i https://pypi.tuna.tsinghua.edu.cn/simple` |
| **apt** | `sources.list` | `mirrors.aliyun.com` |

---

## 三、通用 Nginx 反代模板 ({{APP_NAME}})

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;

    # 接口转发
    location {{API_PREFIX}} {
        proxy_pass         http://{{BACKEND_SERVICE}}:{{BACKEND_PORT}};
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;

        # 长连接/大文件配置
        proxy_read_timeout {{TIMEOUT}};
        proxy_buffering    off;
    }

    # SPA 路由支持
    location / {
        try_files $uri $uri/ /index.html;
    }

    client_max_body_size {{MAX_UPLOAD_SIZE}};
}
```

---

## 四、Docker Compose 编排模板

```yaml
services:
  {{SERVICE_NAME}}:
    build:
      context: {{BUILD_CONTEXT}}
      dockerfile: Dockerfile
    restart: unless-stopped
    env_file: .env
    ports:
      - "{{EXT_PORT}}:{{INT_PORT}}"
    volumes:
      - {{DATA_VOLUME}}:/app/data
    healthcheck:
      test: ["CMD", "{{HEALTH_CHECK_CMD}}"]
      interval: 30s
```

---

## 五、.dockerignore 必选列表

```gitignore
node_modules/
dist/
.env
.git/
*.log
{{CUSTOM_EXCLUDES}}
```
