---
name: Robust Docker Build Strategy
description: 健壮 Docker 构建策略：防止环境变量泄漏及国内网络超时问题，专为 Node.js/Nuxt 项目 Docker 化设计。(A guide to preventing environment variable leakage and network timeouts when Dockerizing Node.js/Nuxt applications, especially in China.)
---

# Robust Docker Build Strategy（健壮 Docker 构建策略）

<!-- 本 Skill 解决 Node.js/Nuxt 应用 Docker 化过程中的两大常见陷阱：环境变量泄漏 & 国内网络超时 -->
This skill addresses common pitfalls when checking the build status of Docker containers for Node.js/Nuxt applications.

## 1. Preventing Environment Variable Leakage（防止环境变量泄漏）

### The Problem（问题根源）
<!-- 从宿主机复制预构建产物时，会把「烘焙」进去的环境变量一并带入容器，导致容器内 localhost 解析错误 -->
Copying pre-built artifacts (e.g., `.output`, `.next`, `dist`) from the host into the container often carries over "baked-in" environment variables (like `DATABASE_URL=127.0.0.1...`). This causes the container to fail when running in the Docker network because `localhost` refers to the container itself, not the host services.

### The Solution: Multi-stage Builds（解决方案：多阶段构建）
<!-- 始终在 Docker 环境内部编译，确保构建环境干净隔离，避免宿主机配置泄漏 -->
Always use multi-stage builds to compile the application **inside** the Docker environment. This ensures:
1.  The build environment is clean and isolated.
2.  Dependencies are installed freshly for the target architecture (e.g., Linux vs Windows).
3.  No host configuration leaks into the image.

**Example Dockerfile Pattern:**

```dockerfile
# Stage 1: Builder
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Production Run
FROM node:20-slim
WORKDIR /app
COPY --from=builder /app/.output ./.output
CMD ["node", ".output/server/index.mjs"]
```

## 2. Resolving Network Timeouts - China Region（解决国内网络超时）

### The Problem（问题根源）
<!-- 官方 Docker 镜像默认使用海外源，国内访问缓慢甚至被阻断，导致 apt-get/npm install 超时 -->
Official Docker images often use `deb.debian.org` or `archive.ubuntu.com` for package updates. In China, these connections can be slow or blocked, causing `apt-get update` or `npm install` to fail with timeouts.

### The Solution: Use Local Mirrors（解决方案：替换为国内镜像源）
<!-- 在 FROM 指令之后立即替换为阿里云/清华等国内镜像源 -->
Replace default sources with region-specific mirrors (e.g., Aliyun, Tsinghua) immediately after the `FROM` instruction.

**For Debian-based images (node:slug, python:slug, etc.):**

```dockerfile
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources
```

**For Alpine-based images:**

```dockerfile
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
```

## 3. Clean Contexts（保持构建上下文干净）
<!-- 通过 .dockerignore 排除 node_modules、构建产物等，避免上下文过大及意外覆盖 -->
Ensure your `.dockerignore` excludes `node_modules` and build storage to prevent context bloat and accidental overwrites.

**Recommended .dockerignore:**
```text
node_modules
.git
.output
.nuxt
dist
.env
```
