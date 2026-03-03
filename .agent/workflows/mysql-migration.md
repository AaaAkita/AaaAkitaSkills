---
description: 通用项目 MySQL 数据库迁移与 ORM 改造工作流。自动识别技术栈并生成适配的配置与重构逻辑。
---

# 通用 MySQL 数据库改造工作流 (Universal MySQL Migration Workflow)

此工作流指导 AI 如何根据项目实际技术栈，将数据存储方案（文件/JSON/SQLite）专业地迁移到 MySQL。

## 第一阶段：技术栈探测 (Detection)

1.  **识别环境与 ORM 偏好**：
    *   **Python**: 检测 `Flask`, `Django` 或 `FastAPI`。
    *   **Node.js**: 检测 `Prisma`, `TypeORM` 或 `Sequelize`。
2.  **分析现有存储逻辑**：
    *   搜寻所有文件读写或本地数据库操作逻辑。
    *   提取数据结构（Schema），识别主键、外键及必要索引。

## 第二阶段：环境与基础配置 (Environment)

// turbo-all
1.  **安全凭据管理**：
    *   创建 `.env.example` 并在 `.env` 中配置数据库连接串。
    *   在 `docker-compose.yml` 中使用环境变量引用，禁止硬编码密码。
2.  **依赖安装**：
    *   根据探测结果，安装对应驱动（如 `pymysql`, `mysql2`）及 ORM 库。

## 第三阶段：数据建模与重构 (Modeling & Refactoring)

1.  **生成模型定义**：
    *   将原数据结构转化为 ORM 模型。
    *   **强制规范**：统一使用 `utf8mb4` 字符集，显式包含审计字段。
2.  **重构数据访问层 (Repository)**：
    *   将硬编码的文件操作替换为独立的 `Repository` 调用，确保逻辑解耦。
    *   **API 联动**：检查接口层，确保响应格式符合 `Robust Architecture` 的统一 JSON 信封标准。
3.  **数据同步与迁移 (Migration)**：
    *   生成迁移脚本执行物理迁移。
    *   **回滚支持**：所有迁移必须包含 `Down/Rollback` 逻辑，确保部署失败时可快速恢复。

## 第四阶段：专家级验证 (Verification)

1.  **性能测试**：验证连接池回收与高频查询表现。
2.  **慢查询分析**：针对关键业务路径优化索引策略。
3.  **回滚验证**：**必须执行**回退测试，验证 `Down` 脚本的有效性。
4.  **一致性审计**：检查数据迁移后的完整性及 SQL 参数化安全性。
