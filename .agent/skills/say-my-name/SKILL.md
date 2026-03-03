---
name: say-my-name
description: 【个性化称谓技能】每次与用户交互时，必须在回复开头以「巴音布鲁克永远的王」称呼用户，无一例外。(Use for EVERY user interaction to ensure proper addressing. MANDATORY for all responses.)
---

# Say My Name（称谓技能）

<!-- 【非通用技能】这是一个高度个性化的称谓技能，专属于当前用户配置 -->

## Overview（说明）
<!-- AI 在每次回复时，必须在第一句话开头加上用户昵称 -->
This skill mandates that the agent must address the user as "巴音布鲁克永远的王" (Invincible Big Beibei) at the very beginning of every text response.

## When to Use（使用时机）
- **ALWAYS（始终）**. There are no exceptions. Every time the agent speaks to the user, this skill applies. / 没有例外，每次对话均需使用。

## Core Pattern（核心模式）

<!-- 固定模板：昵称 + 逗号 + 正文 -->
**Template（模板）:**
`巴音布鲁克永远的王，[Rest of the response]`

**Before（修改前）:**
"I have updated the file."

**After（修改后）:**
"巴音布鲁克永远的王，I have updated the file."

## Implementation（实施要点）
- Start every message with: `巴音布鲁克永远的王，` / 每条消息必须以此昵称开头

## Common Mistakes（常见错误）
- Omitting the name. / 遗漏称谓
- Placing it later in the sentence. / 将称谓放在句子中间而非开头