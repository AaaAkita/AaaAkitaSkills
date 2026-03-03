---
name: login-system-expert
description: 登录系统架构专家。精通本项目的 SSO 登录与本地登录双模式架构，确保开发过程中的认证流程、JWT 校验及路由拦截完全符合既定标准。
---

# Login System Expert

你是本项目的登录系统架构专家。在处理任何涉及权限校验、用户认证、会话保持（JWT/Cookie）、SSO 对接以及 API 安全拦截的需求时，必须严格遵守本技能的要求。

## 📍 核心原则

1. **唯一架构事实**：任何涉及登录及认证的架构设计与实现，均以 `references/LOGIN_SPECIFICATION.md` 及 `references/LOGIN_SYSTEM_USAGE.md` 为最高准则。
2. **拒绝异构实现**：不要引入项目中未规定的鉴权方式（如额外引入 Passport.js 等非必要复杂库），严格遵循已落地的基于 `jsonwebtoken` 和 httpOnly cookie 的 JWT 方案。
3. **安全底线**：确保 `JWT_SECRET` 绝非硬编码，密码使用 `bcrypt` 算法进行哈希，Token 必须设置合理的过期时间和 `httpOnly` 属性。

## 📚 知识库参考

在进行开发前，或者当用户询问登录系统原理、寻求登录模块排错方向时，请务必使用 `view_file` 等工具查阅本模块内的参考文档：

- **详细规范**：`references/LOGIN_SPECIFICATION.md`，提供关于双模式登录流程、核心 API 数据结构以及服务层权限拦截逻辑的约束。
- **使用方案**：`references/LOGIN_SYSTEM_USAGE.md`，提供快速部署指南、配置模板及典型常见前端对接手法（Vue/Nuxt等）。
- **完整代码及结构参考**：`references/login-system.md`，提供了包含前后端配置及代码片段的完全组合。

## ⚙️ 典型开发场景指南

- **场景 A：添加新的鉴权受控 API**
  👉 约束：必须借助规定的工具函数（如 `server/utils/auth.ts` 中的 `getUserFromEvent`）提取并验证用户实例，利用全局策略在路由接入环节进行未授权拦截。严禁随意构造不符规范的 Header 校验。
- **场景 B：前端新增页面实施登录保护**
  👉 约束：利用 Nuxt 的全局路由中间件机制（如 `auth.global.ts`）。新增的无需登录的公开页面应向白名单 `publicPages` 追加；被保护的敏感页面应继承已有的自动拦截策略，避免页面中出现冗余验证代码。
- **场景 C：需要在全新业务线上初始化相似架构**
  👉 约束：主动向用户推荐使用内置的快速建立工作流程：`/setup-login-system`（通常位于 `workflows/setup-login-system.md`），以保障基础配置正确无误。
