# 登录系统使用方案文档

## 1. 系统概述

本登录系统是一个完整的用户认证解决方案，支持两种登录方式：

- **SSO 登录**：通过元数云等第三方认证服务进行登录，适用于普通用户
- **本地登录**：通过手机号和密码进行登录，适用于管理员账号

系统使用 JWT (JSON Web Token) 进行认证，token 存储在 httpOnly cookie 中，提高安全性。

## 2. 安装步骤

### 2.1 前提条件

- Node.js 18+ 环境
- Nuxt 3 项目
- MySQL 数据库

### 2.2 安装依赖

```bash
# 安装核心依赖
npm install bcryptjs jsonwebtoken @prisma/client prisma

# 安装类型定义（TypeScript 项目）
npm install --save-dev @types/bcryptjs @types/jsonwebtoken
```

### 2.3 初始化数据库

```bash
# 初始化 Prisma 配置
npx prisma init

# 运行数据库迁移
npx prisma migrate dev
```

### 2.4 配置环境变量

在项目根目录创建 `.env` 文件：

```env
# JWT 密钥（生产环境必须修改为强密钥）
JWT_SECRET=your-secret-key-change-this-in-production

# 数据库连接字符串
DATABASE_URL=mysql://user:password@localhost:3306/dbname
```

## 3. 系统配置

### 3.1 数据库配置

在 `prisma/schema.prisma` 文件中添加用户模型：

```prisma
datasource db {
  provider = "mysql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}

model User {
  id              String   @id @default(cuid())
  yuanshuyunId    String?  @unique
  phone           String?  @unique
  password        String?
  nickname        String
  avatar          String?
  role            String   @default("USER")
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt
}
```

### 3.2 创建核心文件

按照以下结构创建文件：

```
project/
├── server/
│   ├── utils/
│   │   ├── auth.ts         # 认证工具函数
│   │   └── prisma.ts       # Prisma 客户端初始化
│   └── api/
│       └── auth/
│           ├── login.post.ts       # 本地登录接口
│           ├── logout.post.ts      # 登出接口
│           ├── me.get.ts           # 获取当前用户信息接口
│           └── sso-sync.post.ts    # SSO 同步接口
├── middleware/
│   └── auth.global.ts     # 全局认证中间件
└── pages/
    └── login.vue          # 登录页面
```

## 4. 核心功能使用

### 4.1 登录流程

#### 4.1.1 SSO 登录（普通用户）

1. 用户访问 `/login` 页面
2. 点击 "点击登录" 按钮
3. 系统打开元数云登录窗口
4. 用户在元数云完成登录
5. 系统检测到元数云 cookie 后，自动调用 SSO 同步接口
6. 系统创建或更新本地用户，并生成 JWT token
7. 用户自动跳转到 `/workspace/studio` 页面

#### 4.1.2 本地登录（管理员）

1. 发送 POST 请求到 `/api/auth/login`
2. 请求体包含 `phone` 和 `password`
3. 系统验证密码并生成 JWT token
4. 系统设置 httpOnly cookie
5. 返回用户信息

### 4.2 登出流程

1. 发送 POST 请求到 `/api/auth/logout`
2. 系统清除 token cookie
3. 用户被重定向到登录页面

### 4.3 获取当前用户信息

1. 发送 GET 请求到 `/api/auth/me`
2. 系统验证 token 并返回用户信息
3. 前端根据返回结果判断用户是否已登录

## 5. 前端集成

### 5.1 登录页面

使用提供的 `login.vue` 组件作为登录页面，无需修改。

### 5.2 认证中间件

全局中间件 `auth.global.ts` 会自动检查用户登录状态，未登录用户会被重定向到登录页面。

### 5.3 页面保护

在需要保护的页面中，无需额外配置，中间件会自动处理认证。

### 5.4 获取用户信息

在组件中获取当前用户信息：

```vue
<template>
  <div>
    <div v-if="user">
      <h1>欢迎，{{ user.nickname }}</h1>
      <button @click="logout">登出</button>
    </div>
    <div v-else>
      <p>请先登录</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const user = ref(null)

const fetchUser = async () => {
  try {
    const res = await fetch('/api/auth/me')
    const data = await res.json()
    if (data.success) {
      user.value = data.user
    }
  } catch (error) {
    console.error('获取用户信息失败:', error)
  }
}

const logout = async () => {
  try {
    await fetch('/api/auth/logout', { method: 'POST' })
    window.location.href = '/login'
  } catch (error) {
    console.error('登出失败:', error)
  }
}

onMounted(() => {
  fetchUser()
})
</script>
```

## 6. 后端集成

### 6.1 保护 API 路由

在需要认证的 API 路由中，使用 `getUserFromEvent` 函数验证用户身份：

```typescript
// server/api/protected-route.get.ts
import { getUserFromEvent } from '~/server/utils/auth'
import { defineEventHandler, createError } from 'h3'

export default defineEventHandler(async (event) => {
  const user = await getUserFromEvent(event)
  
  if (!user) {
    throw createError({
      statusCode: 401,
      statusMessage: '未授权访问'
    })
  }
  
  // 处理请求
  return {
    success: true,
    message: '访问成功',
    user
  }
})
```

### 6.2 角色权限控制

根据用户角色进行权限控制：

```typescript
// server/api/admin-only.get.ts
import { getUserFromEvent } from '~/server/utils/auth'
import { defineEventHandler, createError } from 'h3'

export default defineEventHandler(async (event) => {
  const user = await getUserFromEvent(event)
  
  if (!user) {
    throw createError({
      statusCode: 401,
      statusMessage: '未授权访问'
    })
  }
  
  if (user.role !== 'ADMIN') {
    throw createError({
      statusCode: 403,
      statusMessage: '权限不足'
    })
  }
  
  // 处理管理员专用请求
  return {
    success: true,
    message: '管理员访问成功'
  }
})
```

## 7. 常见问题与解决方案

### 7.1 SSO 登录失败

**问题**：用户在元数云登录后，系统无法同步登录状态

**解决方案**：
- 检查浏览器是否允许第三方 cookie
- 确保元数云登录成功并设置了 `BBS_Data1` cookie
- 检查网络连接是否正常
- 查看浏览器控制台是否有错误信息

### 7.2 本地登录失败

**问题**：管理员账号登录失败

**解决方案**：
- 检查手机号和密码是否正确
- 确保用户存在且设置了密码
- 查看服务器日志，确认是否有错误信息

### 7.3 JWT 验证失败

**问题**：用户登录后，访问受保护资源时提示未授权

**解决方案**：
- 检查 `JWT_SECRET` 是否正确设置
- 确保 token 没有过期
- 检查 cookie 是否被正确设置

### 7.4 数据库连接失败

**问题**：系统无法连接到数据库

**解决方案**：
- 检查 `DATABASE_URL` 是否正确
- 确保数据库服务正在运行
- 检查数据库用户权限

## 8. 自定义配置

### 8.1 更换 SSO 提供商

修改 `server/api/auth/sso-sync.post.ts` 文件中的 SSO 接口调用：

```typescript
// 原代码
const userInfoRes = await $fetch('https://bbs.cgpool.com/api/login/getlogininfobycgsaastoken', {
    method: 'POST',
    body: {
        cgsaas_token: bbsToken
    }
})

// 修改为其他 SSO 提供商
const userInfoRes = await $fetch('https://your-sso-provider.com/api/userinfo', {
    method: 'POST',
    headers: {
        'Authorization': `Bearer ${bbsToken}`
    }
})
```

### 8.2 自定义登录成功跳转页面

修改 `pages/login.vue` 文件中的跳转逻辑：

```typescript
// 原代码
if (data.success) {
    // 登录成功，跳转到工作台
    router.push('/workspace/studio')
}

// 修改为其他页面
if (data.success) {
    // 登录成功，跳转到首页
    router.push('/')
}
```

### 8.3 自定义 token 有效期

修改 `server/utils/auth.ts` 文件中的 token 过期时间：

```typescript
// 原代码
export function createToken(payload: JWTPayload): string {
    return jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' })
}

// 修改为其他有效期
export function createToken(payload: JWTPayload): string {
    return jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' }) // 30天
}
```

## 9. 部署注意事项

### 9.1 生产环境配置

- **JWT_SECRET**：必须设置为强密钥，建议使用随机生成的字符串
- **数据库连接**：使用生产环境数据库，确保连接字符串安全
- **HTTPS**：生产环境必须使用 HTTPS，防止 cookie 被窃取
- **CORS**：正确配置 CORS 策略，只允许信任的域名访问

### 9.2 性能优化

- **缓存**：对用户信息进行适当缓存，减少数据库查询
- **数据库索引**：为 `yuanshuyunId` 和 `phone` 字段创建索引
- **错误处理**：完善错误处理机制，避免敏感信息泄露

### 9.3 安全措施

- **密码加密**：使用 bcrypt 对密码进行加密存储
- **Cookie 安全**：设置 httpOnly、secure 和 sameSite 属性
- **输入验证**：对所有用户输入进行严格验证
- **防止暴力破解**：实现登录失败次数限制

## 10. 示例项目

### 10.1 完整项目结构

```
my-project/
├── server/
│   ├── api/
│   │   ├── auth/
│   │   │   ├── login.post.ts
│   │   │   ├── logout.post.ts
│   │   │   ├── me.get.ts
│   │   │   └── sso-sync.post.ts
│   │   └── protected/
│   │       └── data.get.ts
│   └── utils/
│       ├── auth.ts
│       └── prisma.ts
├── middleware/
│   └── auth.global.ts
├── pages/
│   ├── login.vue
│   ├── index.vue
│   └── dashboard.vue
├── prisma/
│   └── schema.prisma
├── .env
├── package.json
└── nuxt.config.ts
```

### 10.2 示例 API 调用

#### 本地登录

```javascript
// 前端调用
const login = async (phone, password) => {
  const res = await fetch('/api/auth/login', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ phone, password })
  })
  return res.json()
}

// 使用示例
const handleLogin = async () => {
  const result = await login('13800138000', 'password123')
  if (result.success) {
    console.log('登录成功:', result.user)
    // 跳转到首页
  } else {
    console.error('登录失败:', result.message)
  }
}
```

#### 获取用户信息

```javascript
// 前端调用
const getUserInfo = async () => {
  const res = await fetch('/api/auth/me')
  return res.json()
}

// 使用示例
const checkLoginStatus = async () => {
  const result = await getUserInfo()
  if (result.success) {
    console.log('用户已登录:', result.user)
  } else {
    console.log('用户未登录')
    // 跳转到登录页
  }
}
```

## 11. 总结

本登录系统提供了一个完整的用户认证解决方案，支持 SSO 登录和本地登录两种方式，使用 JWT 进行认证，具有良好的安全性和用户体验。

系统特点：
- **双模式登录**：支持 SSO 登录和本地登录
- **安全性高**：使用 httpOnly cookie 存储 token，bcrypt 加密密码
- **易于集成**：提供完整的代码模板和使用文档
- **可扩展性强**：支持自定义 SSO 提供商和登录流程
- **权限控制**：基于角色的权限管理

通过本使用方案文档，您可以快速在新项目中集成此登录系统，为用户提供安全、便捷的登录体验。