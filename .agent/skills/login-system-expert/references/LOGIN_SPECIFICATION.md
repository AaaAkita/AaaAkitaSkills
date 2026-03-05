# 登录系统规范

## 1. 架构设计

### 1.1 登录方式

本登录系统支持两种登录方式：

#### 1.1.1 SSO 登录（主要方式）
- **适用场景**：普通用户登录
- **流程**：
  1. 前端打开 SSO 提供商登录窗口
  2. 用户在 SSO 提供商完成登录后，SSO 提供商设置认证 cookie
  3. 前端检测到认证 cookie 后，调用 `/api/auth/sso-sync` 接口
  4. 后端调用 SSO 提供商接口验证 token 并获取用户信息
  5. 后端根据 SSO 用户 ID 查找或创建本地用户
  6. 后端生成 JWT token 并设置为 httpOnly cookie
  7. 前端通过 JWT token 维持本地会话

#### 1.1.2 本地登录（备用方式）
- **适用场景**：管理员账号使用
- **流程**：
  1. 通过手机号和密码登录
  2. 后端使用 bcrypt 验证密码
  3. 成功后生成 JWT token 并设置为 httpOnly cookie

### 1.2 认证机制
- 使用 JWT (JSON Web Token) 进行认证
- token 存储在 httpOnly cookie 中，提高安全性
- 前端通过全局中间件检查登录状态
- 后端通过 `verifyToken` 函数验证 token 有效性
- token 有效期为 7 天

## 2. 接口定义

### 2.1 本地登录接口

**路径**：`POST /api/auth/login`

**请求体**：
```json
{
  "phone": "13800138000",
  "password": "password123"
}
```

**响应**：
```json
{
  "success": true,
  "user": {
    "id": "1",
    "yuanshuyunId": "12345",
    "nickname": "管理员",
    "avatar": "",
    "phone": "13800138000",
    "role": "ADMIN"
  }
}
```

### 2.2 SSO 同步接口

**路径**：`POST /api/auth/sso-sync`

**请求体**：
```json
{
  "bbsToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**响应**：
```json
{
  "success": true,
  "user": {
    "id": "1",
    "yuanshuyunId": "12345",
    "nickname": "用户昵称",
    "role": "USER",
    "articleCount": 0,
    "trainingCount": 0
  }
}
```

### 2.3 获取当前用户信息接口

**路径**：`GET /api/auth/me`

**响应**：
```json
{
  "success": true,
  "user": {
    "id": "1",
    "yuanshuyunId": "12345",
    "nickname": "用户昵称",
    "avatar": "",
    "phone": "13800138000",
    "role": "USER"
  }
}
```

### 2.4 登出接口

**路径**：`POST /api/auth/logout`

**响应**：
```json
{
  "success": true
}
```

## 3. 代码实现

### 3.1 认证工具函数

```typescript
// server/utils/auth.ts
import type { H3Event } from 'h3'
import jwt from 'jsonwebtoken'
import { prisma } from './prisma'

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-this-in-production'

export interface JWTPayload {
    userId: string
    phone?: string          // 可选，仅管理员账号有值
    yuanshuyunId?: string   // SSO 用户标识
}

export async function verifyToken(token: string): Promise<JWTPayload | null> {
    try {
        const decoded = jwt.verify(token, JWT_SECRET) as JWTPayload
        return decoded
    } catch (error) {
        return null
    }
}

export async function getUserFromEvent(event: H3Event) {
    const token = getCookie(event, 'token')

    if (!token) {
        return null
    }

    const payload = await verifyToken(token)

    if (!payload) {
        return null
    }

    try {
        const user = await prisma.user.findUnique({
            where: { id: payload.userId },
            select: {
                id: true,
                yuanshuyunId: true,
                phone: true,
                nickname: true,
                avatar: true,
                role: true,
            }
        })

        return user
    } catch (error) {
        console.error('Error fetching user:', error)
        return null
    }
}

export function createToken(payload: JWTPayload): string {
    return jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' })
}
```

### 3.2 本地登录接口

```typescript
// server/api/auth/login.post.ts
import bcrypt from 'bcryptjs'
import { prisma } from '~/server/utils/prisma'
import { createToken } from '~/server/utils/auth'

export default defineEventHandler(async (event) => {
    const { phone, password } = await readBody(event)

    if (!phone || !password) {
        throw createError({ statusCode: 400, statusMessage: 'Missing phone or password' })
    }

    const user = await prisma.user.findUnique({ where: { phone } })

    if (!user || !user.password) {
        throw createError({
            statusCode: 401,
            statusMessage: 'Invalid credentials'
        })
    }

    const passwordMatch = await bcrypt.compare(password, user.password)

    if (!passwordMatch) {
        throw createError({
            statusCode: 401,
            statusMessage: 'Invalid credentials'
        })
    }

    const token = createToken({
        userId: user.id,
        phone: user.phone ?? undefined,
        yuanshuyunId: user.yuanshuyunId ?? undefined,
    })

    // Set httpOnly cookie
    setCookie(event, 'token', token, {
        httpOnly: true,
        path: '/',
        maxAge: 60 * 60 * 24 * 7, // 7 days
        sameSite: 'lax'
    })

    return {
        success: true,
        user: {
            id: user.id,
            yuanshuyunId: user.yuanshuyunId,
            nickname: user.nickname,
            avatar: user.avatar,
            phone: user.phone,
            role: user.role
        }
    }
})
```

### 3.3 SSO 同步接口

```typescript
// server/api/auth/sso-sync.post.ts
import { prisma } from '~/server/utils/prisma'
import { createToken } from '~/server/utils/auth'

export default defineEventHandler(async (event) => {
    const body = await readBody(event)
    const bbsToken = body.bbsToken

    if (!bbsToken) {
        throw createError({
            statusCode: 400,
            statusMessage: '缺少SSO认证Token'
        })
    }

    // 调用SSO提供商接口获取用户信息
    const userInfoRes = await $fetch('https://bbs.cgpool.com/api/login/getlogininfobycgsaastoken', {
        method: 'POST',
        body: {
            cgsaas_token: bbsToken
        }
    })

    if (!userInfoRes || !userInfoRes.success || !userInfoRes.data || !userInfoRes.data.user) {
        throw createError({
            statusCode: 401,
            statusMessage: '无效的SSO Token或未登录'
        })
    }

    const ssoUser = userInfoRes.data.user
    const yuanshuyunId = String(ssoUser.id)
    const nickname = ssoUser.nickname || '新用户'
    const avatar = ssoUser.avatar || ''

    // 查找或创建本地用户
    let user = await prisma.user.findUnique({
        where: { yuanshuyunId }
    })

    if (!user) {
        user = await prisma.user.create({
            data: {
                yuanshuyunId,
                nickname,
                avatar,
                role: 'USER',
            }
        })
    } else {
        // 每次登录同步更新昵称和头像
        if (user.nickname !== nickname || user.avatar !== avatar) {
            user = await prisma.user.update({
                where: { id: user.id },
                data: { nickname, avatar }
            })
        }
    }

    // 签发本地 JWT token
    const token = createToken({
        userId: user.id,
        yuanshuyunId: user.yuanshuyunId ?? undefined,
    })

    // 设置 httpOnly Cookie
    setCookie(event, 'token', token, {
        httpOnly: true,
        path: '/',
        maxAge: 60 * 60 * 24 * 7, // 7 天
        sameSite: 'lax'
    })

    return {
        success: true,
        user: {
            id: user.id,
            yuanshuyunId: user.yuanshuyunId,
            nickname: user.nickname,
            role: user.role
        }
    }
})
```

### 3.4 获取当前用户信息接口

```typescript
// server/api/auth/me.get.ts
import { getUserFromEvent } from '~/server/utils/auth'

export default defineEventHandler(async (event) => {
    const user = await getUserFromEvent(event)

    if (!user) {
        throw createError({
            statusCode: 401,
            statusMessage: 'Not authenticated'
        })
    }

    return {
        success: true,
        user
    }
})
```

### 3.5 登出接口

```typescript
// server/api/auth/logout.post.ts
export default defineEventHandler(async (event) => {
    // 清除 token cookie
    deleteCookie(event, 'token')

    return {
        success: true
    }
})
```

### 3.6 前端登录页面

```vue
<template>
  <div class="min-h-screen bg-gray-50 flex flex-col justify-center items-center py-12 sm:px-6 lg:px-8">
    <div class="sm:mx-auto sm:w-full sm:max-w-md text-center">
      <h2 class="text-3xl font-extrabold text-gray-900">
        {{ message }}
      </h2>
      <p class="mt-2 text-sm text-gray-500">
        {{ subMessage }}
      </p>
    </div>
    <div class="mt-8 flex flex-col items-center gap-4">
      <div v-if="loading" class="w-8 h-8 border-4 border-blue-500 border-t-transparent rounded-full animate-spin" />
      <div v-else-if="error" class="text-red-500 text-sm">
        {{ error }}
      </div>
      <button
        v-if="showLoginButton"
        class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
        @click="openLoginWindow"
      >
        点击登录
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'

const router = useRouter()

// 页面元数据
definePageMeta({ layout: false })

const message = ref('正在验证登录状态...')
const subMessage = ref('正在检查登录状态...')
const showLoginButton = ref(false)
const loading = ref(true)
const error = ref('')

// 打开登录窗口
const openLoginWindow = () => {
  const redirectUri = encodeURIComponent(window.location.origin + '/workspace/studio')
  const loginUrl = `https://www.cgpool.com/web_site_front/login/loginPage?redirect_uri=${redirectUri}`
  
  // 打开新窗口
  const loginWindow = window.open(loginUrl, 'loginWindow', 'width=800,height=600,top=100,left=100')
  
  // 检查窗口是否关闭
  const checkWindowClosed = setInterval(() => {
    if (loginWindow && loginWindow.closed) {
      clearInterval(checkWindowClosed)
      // 窗口关闭后检查登录状态
      checkLoginStatus()
    }
  }, 1000)
}

const checkLoginStatus = async () => {
  message.value = '正在验证登录状态...'
  subMessage.value = '正在检查登录状态...'
  showLoginButton.value = false
  loading.value = true
  error.value = ''
  
  try {
    // 检查是否有SSO的cookie
    const checkCookie = (name: string) => {
      const cookieValue = document.cookie
        .split('; ')
        .filter(row => row.startsWith(name + '='))[0]
        ?.split('=')[1]
      return cookieValue
    }
    
    const bbsToken = checkCookie('BBS_Data1') || checkCookie('token-webSite') || checkCookie('BBS_Data')
    
    if (bbsToken) {
      // 调用SSO同步接口
      const res = await fetch('/api/auth/sso-sync', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ bbsToken })
      })
      
      const data = await res.json()
      
      if (data.success) {
        // 登录成功，跳转到工作台
        router.push('/workspace/studio')
      } else {
        // 同步失败，显示登录按钮
        message.value = '请先登录'
        subMessage.value = '点击下方按钮打开登录窗口'
        showLoginButton.value = true
      }
    } else {
      // 没有SSO cookie，显示登录按钮
      message.value = '请先登录'
      subMessage.value = '点击下方按钮打开登录窗口'
      showLoginButton.value = true
    }
  } catch (err) {
    console.error('Login check error:', err)
    message.value = '请先登录'
    subMessage.value = '点击下方按钮打开登录窗口'
    showLoginButton.value = true
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  // 检查是否是从SSO登录后重定向回来的
  const code = new URLSearchParams(window.location.search).get('code')
  
  if (code) {
    message.value = '登录成功，正在处理...'
    subMessage.value = '正在同步登录状态...'
    // 给一点时间让浏览器设置cookie
    setTimeout(() => {
      checkLoginStatus()
    }, 1000)
  } else {
    checkLoginStatus()
  }
})
</script>
```

### 3.7 前端认证中间件

```typescript
// middleware/auth.global.ts
import { useRouter } from 'vue-router'

export default defineNuxtRouteMiddleware(async (to) => {
  const router = useRouter()
  
  // 不需要认证的页面
  const publicPages = ['/login', '/register']
  const isPublicPage = publicPages.includes(to.path)
  
  if (isPublicPage) {
    return
  }
  
  try {
    // 检查登录状态
    const res = await fetch('/api/auth/me')
    const data = await res.json()
    
    if (!data.success) {
      // 未登录，重定向到登录页
      return router.push('/login')
    }
  } catch (error) {
    // 请求失败，重定向到登录页
    return router.push('/login')
  }
})
```

## 4. 配置要求

### 4.1 环境变量

| 变量名 | 类型 | 必填 | 描述 |
|-------|------|------|------|
| JWT_SECRET | string | 是 | JWT 签名密钥 |
| DATABASE_URL | string | 是 | 数据库连接字符串 |

### 4.2 数据库表结构

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

## 5. 依赖项

| 依赖 | 版本 | 用途 |
|------|------|------|
| bcryptjs | ^2.4.3 | 密码加密 |
| jsonwebtoken | ^9.0.2 | JWT 生成和验证 |
| @prisma/client | ^5.0.0 | 数据库操作 |
| prisma | ^5.0.0 | 数据库迁移 |

## 6. 使用说明

### 6.1 安装依赖

```bash
npm install bcryptjs jsonwebtoken @prisma/client prisma
```

### 6.2 初始化数据库

```bash
npx prisma init
npx prisma migrate dev
```

### 6.3 配置环境变量

在 `.env` 文件中添加：

```env
JWT_SECRET=your-secret-key-change-this-in-production
DATABASE_URL=postgresql://user:password@localhost:5432/dbname
```

### 6.4 启动服务

```bash
npm run dev
```

## 7. 安全与跨域避坑指南（关键）

1. **JWT_SECRET**：必须在生产环境中设置为强密钥，并定期更换
2. **密码存储**：使用 bcrypt 对密码进行加密存储，禁止明文存储密码
3. **Cookie 安全**：设置 httpOnly 和 sameSite 属性。跨域部署时，**必须确保主应用域名与 SSO 服务提供商挂载在同一顶级域名下（或配置正确的子域名映射）**，否则前端绝对无法读取 SSO 颁发的鉴权 Cookie。
4. **拒绝对 SSO Token 接口进行本地 Mock（防查库灾难）**：在前端代码 `login.vue / login.html` 发生无法获取 token 的情况下，应直接向用户报错。**绝对禁止**在逻辑中加入“如果拿不到线上 Token 就读取本地 `BBS_Data.json` 获取定值 Token”的兜底代码。这会导致所有尝试登录的用户均带着同一个测试用 Token 同步给后端，最终造成数据库里出现所有人覆盖注册到同一条用户数据（唯一 ID 冲突）的严重生产事故。
5. **SSO 验证后端调用规范**：后端代理验证 `bbsToken`，调用第三方如 `https://bbs.cgpool.com/...` 时，在发起网络请求（`fetch` 或 `requests.post`）时，**必须使用 `application/x-www-form-urlencoded` 表单格式 (如 Python 的 `data={'cgsaas_token': token}` 或 JS 的 `new URLSearchParams()`) 传递参数**，不能使用 `application/json` (如 `json={...}`)，否则将遭遇第三方服务器防跨域或严格参数解析引发的 HTTP 401 Unauthorized 错误。
6. **重定向拦截器参数保留**：任何全局未登录拦截器（如 Flask `@login_required` 或 Nuxt Middleware）在遇到含 `?code=xxxx` 的 SSO 回跳时，在强行执行 Redirect 转往 `login` 页时，**必须保留并透传原 URL 上的所有 Query String** 避免授权码在跳转路由间丢失。

## 8. 扩展建议

1. **多因素认证**：添加短信验证码或邮箱验证
2. **密码重置**：实现密码重置功能
3. **第三方登录**：支持微信、QQ 等第三方登录
4. **登录日志**：记录登录历史，便于审计和异常检测
5. **Token 刷新**：实现 token 自动刷新机制

## 9. 示例项目结构

```
project/
├── server/
│   ├── api/
│   │   └── auth/
│   │       ├── login.post.ts
│   │       ├── logout.post.ts
│   │       ├── me.get.ts
│   │       └── sso-sync.post.ts
│   ├── utils/
│   │   ├── auth.ts
│   │   └── prisma.ts
│   └── middleware/
│       └── auto-login.ts
├── middleware/
│   └── auth.global.ts
├── pages/
│   ├── login.vue
│   ├── register.vue
│   └── workspace/
│       └── studio.vue
├── prisma/
│   └── schema.prisma
├── .env
└── package.json
```
