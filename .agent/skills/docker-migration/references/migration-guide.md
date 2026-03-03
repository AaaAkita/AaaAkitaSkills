# Docker 项目迁移与部署通用指南 (Windows -> Linux)

本指南旨在帮助非专业开发人员将 Docker 项目从 Windows 开发环境顺利迁移至 Linux 服务器。

---

## 第一阶段：环境准备与端口规划

### 1. 硬件与网络准备
- **领取端口**: 联系网络管理员（如 WHK）确认服务器可用的公网端口。
- **镜像加速 (国内环境必备)**:
    由于国内网络环境，构建镜像前请配置国内镜像源以加快下载速度。
    - **Windows (Docker Desktop)**: 
        1. 打开设置 (Settings) -> Docker Engine。
        2. 在 JSON 配置文件中添加 (或修改) `"registry-mirrors"`，例如：
           ```json
           {
             "registry-mirrors": [
               "https://api.daocloud.io",
               "https://hub-mirror.c.163.com",
               "https://mirror.baidubce.com"
             ]
           }
           ```
        3. 点击 "Apply & Restart"。

### 2. 端口记录示例
建议记录如下表格，防止端口冲突：
| 服务名称 | 内部端口 | 外部映射端口 (由 WHK 分配) |
| :--- | :--- | :--- |
| 主应用 (Frontend) | 3000 | `[主端口]` (如 5223) |
| 管理后台 (Admin) | 3000 | `[次端口]` (如 5225) |
| 数据库 (DB) | 5432 | 不对外开放 |

---

## 第二阶段：Windows 本地部署与验证

### 1. 启动项目 (详细步骤)
对于非专业人员，启动项目仅需四步：

1.  **找到项目文件夹**: 在资源管理器中打开包含 `docker-compose.yml` 的项目根目录。
2.  **打开终端**:
    - **方法一**: 在文件夹空白处按住 `Shift` 键并点击鼠标右键，选择 **"在此处打开 Powershell 窗口"** 或 **"Open in Terminal"**。
    - **方法二 (IDE)**: 如果使用 VS Code 等编辑器，在左侧资源管理器空白处右键选择 **"Open in Integrated Terminal"** (在集成终端中打开)。
3.  **输入启动命令**:
    ```powershell
    # -d 表示在后台运行，--build 表示强制重新构建镜像
    docker compose up -d --build
    ```
4.  **确认启动**: 终端显示绿色 `Started` 或 `Running` 字样即为成功。

### 2. 数据库数据同步 (从本地导入 Docker)
为了让 Docker 环境拥有和你本地开发环境一样的数据，需要执行数据导入。

**场景一：利用备份文件还原**
如果你有 `.sql` 备份文件 (例如 `backup.sql`)：
```powershell
# 将 SQL 文件内容导入到 Docker 数据库容器中
# 假设容器名为 cnovel-db-1，数据库用户为 postgres
cat backup.sql | docker exec -i cnovel-db-1 psql -U postgres
```

**场景二：利用脚本初始化 (Seed)**
如果项目提供了初始化脚本 (如 `npm run seed`)，请先进入容器或在本地连接容器数据库执行：
```powershell
# 例如，在 backend 容器中执行种子脚本
docker compose exec app npm run seed
```

**验证**: 在本地浏览器访问 `http://localhost:[外部映射端口]` 确认数据已显示。

---

## 第三阶段：导出与打包 (AI 协助)

### 1. 导出镜像与数据 (关键步骤)
这一步涉及复杂的命令行操作，**强烈建议直接复制以下指令发送给 AI 助手**，让它帮你执行。

> **给 AI 的指令**:
> "请帮我将当前运行的 Docker 镜像导出为 .tar 文件。
> 同时，请帮我将数据库中的数据导出为 `data.sql`。
> **注意**: 导出 SQL 时请务必使用 `cmd /c` 和 `pg_dumpall` 组合，并加上 `-c` (clean) 参数，**绝对不要**使用 `-t` (TTY) 模式，以防止生成的文件包含乱码或控制字符，导致 Linux 导入失败。"

**AI 执行的技术细节 (供参考)**:
- **镜像导出**: `docker save -o [镜像名].tar [镜像名]:latest`
- **无乱码 SQL 导出**: 
  ```powershell
  # 重点：不使用 -t 参数，使用 cmd /c 确保管道符正确处理字符编码
  cmd /c "docker exec -i [数据库容器名] pg_dumpall -c -U postgres > data.sql"
  ```

### 2. 文件整理与打包
你可以要求 AI 助手：“请帮我把部署所需的所有文件（docker-compose.yml, .env, .tar 镜像包, data.sql 数据库文件）整理到一个名为 `linux-deploy` 的文件夹中并打包为 zip。”

---

## 第四阶段：Linux 服务器部署

### 1. 远程文件传输
将 `linux-deploy.zip` 上传至 Linux 服务器的指定目录（如 `~/Desktop/my-project`）并解压。

### 2. 加载与启动 (Linux 终端)
在 Linux 终端中进入解压后的目录，执行：

```bash
# 1. 加载镜像文件 (如果有多个镜像，请分别加载)
sudo docker load -i [镜像名].tar

# 2. 启动服务
sudo docker compose up -d

# 3. 导入数据库 (确保 sql 文件没有乱码)
cat data.sql | sudo docker exec -i [数据库容器名] psql -U postgres
```

### 3. 放行防火墙 (必须)
这是外网能否访问的关键！
```bash
# Ubuntu/Debian 示例 (UFW)
sudo ufw allow [主端口]/tcp
sudo ufw allow [次端口]/tcp

# 验证防火墙状态
sudo ufw status
```

---

## 避坑指南 (FAQ)
1.  **连接超时**: 
    - 检查 Linux 的防火墙 (`ufw status`)。
    - **最常见原因**：云服务器厂商（阿里云/腾讯云）的网页控制台“安全组”未开放对应端口。务必去网页端检查。
2.  **SQL 导入报错**: 
    - 如果提示 `invalid byte sequence`，通常是导出时不仅包含了数据，还包含了终端的彩色控制符。请参考第三阶段的“无乱码 SQL 导出”重新导出。
3.  **权限不足**: 
    - Linux 下操作 Docker 通常需要 `sudo`，如果嫌麻烦可以将用户加入 docker 组。
