---
description: 通用项目 Docker 部署改造流程。自动识别技术栈并生成适配的 Dockerfile, docker-compose.yml 和 .dockerignore。
---

# 通用 Docker 部署改造工作流 (Universal Dockerize Workflow)

此工作流指导 AI 如何根据项目的实际技术栈，自动生成符合最佳实践的 Docker 配置文件。

## 第一阶段：深度探测 (Detection)

1.  **识别核心技术栈**：
    *   **Node.js**: 存在 `package.json`。
    *   **Python**: 存在 `requirements.txt`, `pipfile`, `pyproject.toml` 或 `app.py`。
    *   **Go**: 存在 `go.mod`。
    *   **Java/Spring**: 存在 `pom.xml` 或 `build.gradle`。
    *   **Static/Frontend**: 仅包含 HTML/JS/CSS 或 `index.html`。
2.  **定位关键要素**：
    *   **端口**: 搜索代码中的 `listen`, `port`, `app.run` 等关键字。
    *   **持久化目录**: 识别存储上传文件、日志或数据库产物的目录（如 `/uploads`, `/data`, `/logs`）。
    *   **系统依赖**: 检查是否需要 `ffmpeg`, `imagemagick`, `libpq` 等系统级工具。

## 第二阶段：生成通用标准配置 (Generation)

// turbo-all
1.  **生成 `.dockerignore` (通用模板)**：
    *   使用通用排除项：`.git`, `.env`, `__pycache__`, `node_modules`, `dist`, `build`, `.vscode`, `.idea`。
    *   **大文件清理**：必须排除所有大型压缩包（`*.zip`, `*.7z`, `*.rar`, `*.tar.gz`）以及与目标容器系统不兼容的二进制执行文件（如 Windows 下的 `.exe` 或 `.dll` ）。

2.  **生成 `Dockerfile` (技术栈适配)**：
    *   **镜像选择**：
        *   Node: `node:XX-alpine`
        *   Python: `python:3.X-slim` 或 `alpine`
        *   Go/Rust: 使用多阶段构建，最终镜像设为 `scratch` 或 `alpine`。
    *   **加速构建**：集成中国区镜像源（阿里云/清华源）。
    *   **安全加固**：创建非 root 用户并使用 `USER` 指令切换权限。
    *   **环境一致性**：设置默认时区环境变量（如 `ENV TZ=Asia/Shanghai`）。
    *   **分层缓存**：始终先复制依赖声明文件，再执行安装，最后复制源码。

3.  **生成 `docker-compose` (多环境支持)**：
    *   **开发环境 (`docker-compose.yml`)**：配置 `volumes: - .:/app` 以支持热更新。
    *   **生产环境 (`docker-compose.prod.yml`)**：
        *   移除源码挂载，配置 `restart: always`。
        *   **健康检查**：添加 `healthcheck` 配置以确保服务可用性。
        *   **安全限制**：尽量使用 `read_only: true` 配合临时目录挂载。

## 第三阶段：交付与优化建议 (Optimization)

1.  **验证构建**：尝试运行 `docker build` 或 `docker compose build`。
2.  **最佳实践报告**：向用户说明选择特定基础镜像的原因，以及如何管理敏感信息。
