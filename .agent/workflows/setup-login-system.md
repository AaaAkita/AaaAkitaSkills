---
description: 登录系统（双模式）一键初始化工作流
---

# /setup-login-system 工作流

本工作流旨在为一个新的 Node 栈（如 Nuxt 3）项目快速初始化完善的“SSO + 本地”双模式登录系统。系统采用基于 Prisma (MySQL) + JWT 方案。

在执行本工作流时，请始终参考 `login-system-expert` 技能中 `references` 目录下的相关详细规范文档（特别是 `LOGIN_SYSTEM_USAGE.md` ），按标准提取具体代码并在业务工程中织入。

## 执行步骤

### Step 1: 扫描并安装核心依赖库
- 首先检查 `package.json`，缺失时使用 `run_command` 为项目安装核心认证库与 ORM 模块。
```bash
// turbo
npm install bcryptjs jsonwebtoken @prisma/client prisma
```
```bash
// turbo
npm install --save-dev @types/bcryptjs @types/jsonwebtoken
```

### Step 2: 编排与同步数据库架构
- 若为全新工程，请先初始化 Prisma。
```bash
// turbo
npx prisma init
```
- **配置数据模型**：在项目中的 `prisma/schema.prisma` 新增 `User` 数据模型（包含关联到 SSO 的 `yuanshuyunId`, 用于本地密码登录的 `phone`/`password`，以及 `nickname`, `avatar`, `role` 等必需字段）。具体结构务必查阅参照文档。

### Step 3: 约束环境变量配置
- 检查或创建项目环境约束文件 `.env`。
- 断言该文件内配置了合理的 `JWT_SECRET`（应当随机生成强密码串）及指向目标 MySQL 数据库的 `DATABASE_URL`。

### Step 4: 挂载核心服务文件与中间层
根据规范，必须分层实现后端逻辑：
- **安全工具包**：在 `server/utils/` 下生成 `auth.ts`（用于 JWT 验证、签发、提取 Cookie）及 `prisma.ts`。
- **控制器接口**：在 `server/api/auth/` 目录下完成 `login.post.ts`（提供密码登录点）、`sso-sync.post.ts`（对接第三方 SSO 并进行账户关联与信息落表）、`me.get.ts`（用于获取自我状态）、`logout.post.ts`（阻断清理动作）。
*💡 提示：此部分全部标准实现已固化于 `login-system-expert/references/LOGIN_SPECIFICATION.md` 的代码段，直接提取并适配路径即可验证生效。*

### Step 5: 注入前端拦截网
- **统一接入卡口**：实施无感拦截策略，创建 `middleware/auth.global.ts`。
- **入口页面**：提供附带 SSO 唤起 popup 和本地登录备用的登录承载页，放置于 `pages/login.vue`。

### Step 6: 数据库结构同步反馈
- 向用户提请运行数据表变更合并的步骤，建议采用：
```bash
npx prisma migrate dev --name init_login_system
```

### Step 7: 交付与联调自测
- 报告所有组件置入完成情况。提示用户运行应用测试访问登录页及其他强制鉴权路由。
- 询问用户是否有定制第三方 SSO 域名或者增强 token 刷新机制等进阶诉求。
