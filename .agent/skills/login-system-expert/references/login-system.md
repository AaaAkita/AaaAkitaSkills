# 登录系统生成器

## 功能描述

本技能用于在项目中生成完整的登录系统，支持SSO登录和本地管理员登录两种方式。

## 生成步骤

### 1. 检查项目环境
- 检查是否为Nuxt 3项目
- 检查是否已安装必要依赖

### 2. 安装依赖
```bash
npm install bcryptjs jsonwebtoken @prisma/client prisma
```

### 3. 生成文件结构

#### 3.1 认证工具函数
- `server/utils/auth.ts`

#### 3.2 API接口
- `server/api/auth/login.post.ts`
- `server/api/auth/logout.post.ts`
- `server/api/auth/me.get.ts`
- `server/api/auth/sso-sync.post.ts`

#### 3.3 前端页面
- `pages/login.vue`

#### 3.4 中间件
- `middleware/auth.global.ts`

#### 3.5 数据库配置
- `prisma/schema.prisma`

### 4. 配置环境变量
在 `.env` 文件中添加：
```env
JWT_SECRET=your-secret-key-change-this-in-production
DATABASE_URL=mysql://user:password@localhost:3306/dbname
```

### 5. 初始化数据库
```bash
npx prisma init
npx prisma migrate dev
```

## 代码模板

### 认证工具函数
```typescript
// server/utils/auth.ts
import type { H3Event } from 'h3'
import jwt from 'jsonwebtoken'
import { prisma } from './prisma'
import { getCookie } from 'h3'

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

### 本地登录接口
```typescript
// server/api/auth/login.post.ts
import bcrypt from 'bcryptjs'
import { prisma } from '~/server/utils/prisma'
import { createToken } from '~/server/utils/auth'
import { defineEventHandler, readBody, setCookie, createError } from 'h3'

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

### SSO 同步接口
```typescript
// server/api/auth/sso-sync.post.ts
import { prisma } from '~/server/utils/prisma'
import { createToken } from '~/server/utils/auth'
import { defineEventHandler, readBody, setCookie, createError } from 'h3'
import { $fetch } from 'ofetch'

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

### 获取当前用户信息接口
```typescript
// server/api/auth/me.get.ts
import { getUserFromEvent } from '~/server/utils/auth'
import { defineEventHandler, createError } from 'h3'

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

### 登出接口
```typescript
// server/api/auth/logout.post.ts
import { defineEventHandler, deleteCookie } from 'h3'

export default defineEventHandler(async (event) => {
    // 清除 token cookie
    deleteCookie(event, 'token')

    return {
        success: true
    }
})
```

### 前端登录页面
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

### 前端认证中间件
```typescript
// middleware/auth.global.ts
import { useRouter } from 'vue-router'
import { defineNuxtRouteMiddleware } from 'nuxt/app'

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

### 数据库配置
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

## 使用方法

1. 在项目根目录执行：
   ```bash
   trea run login-system
   ```

2. 按照提示完成配置

3. 启动项目：
   ```bash
   npm run dev
   ```

4. 访问 `/login` 页面进行登录

## 注意事项

- 本登录系统默认使用元数云作为SSO提供商，如需更换其他SSO提供商，请修改 `sso-sync.post.ts` 中的SSO接口调用
- 生产环境中必须修改 `JWT_SECRET` 为强密钥
- 数据库连接字符串需要根据实际情况修改
- 首次使用需要初始化数据库并创建管理员账号
