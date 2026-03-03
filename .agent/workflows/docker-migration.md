---
description: 将 Docker 项目从 Windows 环境平滑迁移至 Linux 服务器。
---

# Docker 项目迁移指南 (Windows -> Linux)

本工作流引导你完成从 Windows 开发环境到 Linux 生产环境的完整迁移。

### 1. 计划与端口准备
1. 确定 Linux 服务器可用端口。
2. 更新端口映射表 (Frontend, Admin, DB)。

### 2. 本地验证与备份
1. 在 Windows 本地运行项目：
// turbo
```powershell
docker compose up -d --build
```
2. 导出所有 Docker 镜像：
// turbo
```powershell
docker save -o [image_name].tar [image_name]:latest
```
3. 导出数据库（清理 TTY 字符）：
// turbo
```powershell
cmd /c "docker exec -i [db_container_name] pg_dumpall -c -U postgres > data.sql"
```

### 3. 数据打包与传输
1. **修改 `docker-compose.yml`**: 去除所有的 `build:` 及其 `context:` 源码路径配置，并替换为 `image: [image_name]:latest`，以防止在缺乏源码的 Linux 环境下报 `unable to prepare context`。
2. 将修改后的 `docker-compose.yml`, `.env`, `*.tar`, `data.sql` 打包为 `deploy.zip`。
3. 使用 SCP 或 FTP 将包传输至 Linux 服务器。

### 4. Linux 部署环境
1. 在 Linux 上解压并加载镜像：
// turbo
```bash
sudo docker load -i [image_name].tar
```
2. 启动容器：
// turbo
```bash
sudo docker compose up -d
```

### 5. 恢复数据与网络配置
1. 导入数据库：
// turbo
```bash
cat data.sql | sudo docker exec -i [db_container_name] psql -U postgres
```
2. 配置防火墙：
// turbo
```bash
sudo ufw allow [Port]/tcp
```

### 6. 最终验证
1. 访问公网 IP + 端口以确保服务正常。
