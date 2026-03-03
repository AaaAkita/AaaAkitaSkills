---
description: 按照 Robust Architecture 规范一键初始化项目目录结构与基础配置文件。
---

# 项目架构初始化 (Robust Architecture)

本工作流将根据当前项目的 `robust-architecture` 技能规范，快速构建项目骨架。

### 1. 目录结构创建
执行以下命令创建标准分层目录：
// turbo
```powershell
New-Item -ItemType Directory -Path "frontend", "backend", "db/migrations", "db/seeds", "data/tmp", "logs", "tools", "docs", "tests" -Force
```

### 2. 基础文件配置
1. 创建 `.gitignore` 并忽略动态数据：
// turbo
```powershell
$ignoreContent = @"
node_modules/
.env
data/
logs/
*.log
*.tar
dist/
"@
Set-Content -Path ".gitignore" -Value $ignoreContent
```
2. 复制 Skill 中的模板文件 (如 Dockerfile, API 响应模板) 到项目根目录。

### 3. 运维工具部署
从 Skill 的资源库中获取并初始化脚本：
1. `monitor.sh` -> `./tools/monitor.sh`
2. `cleanup.sh` -> `./tools/cleanup.sh`

### 4. 架构师确认
完成目录创建后，参照 `robust-architecture` 技能中的 “健壮性自查清单” 确认项目基础配置是否就绪。
