---
name: Docker Project Migration (Windows to Linux)
description: Docker 项目从 Windows 本地环境迁移至 Linux 服务器的完整指南，涵盖端口规划、数据同步与生产环境部署。(A comprehensive guide for migrating Docker projects from a local Windows environment to a Linux server, including port planning, data synchronization, and deployment.)
---

# Docker Project Migration（Windows → Linux 迁移）

<!-- 本 Skill 指导将 Docker 化应用从 Windows 本地完整迁移至 Linux 生产环境的全过程 -->
This skill guiding the complete process of migrating a Dockerized application from Windows to a Linux production environment.

## 1. Preparation & Port Planning (准备阶段)

### Hardware & Network
- **Acquire Ports**: Contact the network administrator (e.g., WHK) to get available public ports.
- **Configure Registry Mirrors**: Essential for domestic network environments to speed up image builds.
    - **Windows**: Docker Engine -> JSON Config -> Add `"registry-mirrors"`.
    - Recommended mirrors: `https://api.daocloud.io`, `https://hub-mirror.c.163.com`, `https://mirror.baidubce.com`.

### Port Documentation
Maintain a clear record to avoid conflicts:
| Service | Internal Port | External Port (Assigned) |
| :--- | :--- | :--- |
| Frontend | 3000 | `[FrontPort]` (e.g., 5223) |
| Admin | 3000 | `[AdminPort]` (e.g., 5225) |
| Database | 5432 | N/A (Internal only) |

## 2. Windows Local Deployment (本地部署)

### Start Project
1.  **Open Terminal**: 
    - Right-click in the project folder with `Shift` pressed -> "Open PowerShell window here".
    - Or use IDE (VS Code) "Open in Integrated Terminal".
2.  **Execute Command**:
    ```powershell
    docker compose up -d --build
    ```
3.  **Verify**: Check for "Started" or "Running" status in terminal.

### Data Synchronization
- **Restore from Backup**:
    ```powershell
    cat backup.sql | docker exec -i [db_container_name] psql -U postgres
    ```
- **Run Seed Script**:
    ```powershell
    docker compose exec [app_service_name] npm run seed
    ```

## 3. Export & Packaging (导出打包)

### Export Images & Clean Data（导出镜像与清理数据）
<!-- 关键：必须使用特定命令以避免乱码和 TTY 控制字符污染 SQL 文件 -->
**CRITICAL**: Use specific commands to avoid encoding issues (乱码) and TTY control characters.

- **Export Image**:
    ```powershell
    docker save -o [image_name].tar [image_name]:latest
    ```
- **Export Data (Clean SQL)**:
    ```powershell
    cmd /c "docker exec -i [db_container_name] pg_dumpall -c -U postgres > data.sql"
    ```

### Package Artifacts
1.  **Modify `docker-compose.yml` (CRITICAL)**: Open the file and replace all `build:` blocks with corresponding `image: [image_name]:latest` definitions. This is required to prevent "unable to prepare context" errors when starting containers on the Linux server without source code. 
    <!-- 关键：在 Linux 下由于没有代码本源，如果不移除 build 节点而尝试执行 compose up 将会导致致命错误。 -->
2.  Organize the following into a `linux-deploy` folder and zip it:
- `docker-compose.yml` (Modified)
- `.env`
- `*.tar` (Image files)
- `data.sql` (Database dump)

## 4. Linux Deployment (Linux 部署)

### Transfer & Load
1.  **Upload**: Transfer `linux-deploy.zip` to the server (e.g., `~/Desktop/my-project`).
2.  **Load Images**:
    ```bash
    sudo docker load -i [image_name].tar
    ```
3.  **Start Services**:
    ```bash
    sudo docker compose up -d
    ```

### Import Data
1.  **Import SQL**:
    ```bash
    cat data.sql | sudo docker exec -i [db_container_name] psql -U postgres
    ```

### Networking
1.  **Firewall (UFW)**:
    ```bash
    sudo ufw allow [FrontPort]/tcp
    sudo ufw allow [AdminPort]/tcp
    ```
2.  **Cloud Security Group**: Ensure ports are open in the cloud provider's console (critical for connection timeouts).

## Troubleshooting（常见问题排查）

- **Connection Refused（连接拒绝）**: Check local firewall (`ufw status`) AND cloud security groups. / 检查本地防火墙（`ufw status`）及云控制台安全组配置。
- **SQL Errors / `invalid byte sequence`（乱码/非法字节序列）**: Re-export data using the `cmd /c` method without `-t` (TTY). / 请使用 `cmd /c` 方式重新导出，避免携带 TTY 控制字符。
- **Permission Denied（权限不足）**: Prefix commands with `sudo` or add user to `docker` group. / 在命令前加 `sudo`，或将当前用户加入 `docker` 用户组。

---

## 参考文档

<!-- 当团队中有非技术人员需要操作，或需要完整的分阶段操作手册时，可查阅以下参考文档 -->

| 文件 | 说明 |
|------|------|
| [migration-guide.md](references/migration-guide.md) | 面向非专业人员的完整迁移操作手册：含端口规划、本地验证、导出打包、Linux 部署全流程图文说明，以及避坑指南 |
