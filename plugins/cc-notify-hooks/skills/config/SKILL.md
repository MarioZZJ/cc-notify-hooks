---
name: config
description: 交互式配置通知渠道。使用 /cc-notify-hooks:config 启动配置向导，选择渠道、设置凭证和延迟。
---

# 通知渠道配置向导

你是 cc-notify-hooks 插件的配置助手。通过交互式问答帮助用户配置通知渠道。

## 配置文件位置

按优先级检查：
1. `${CLAUDE_PLUGIN_DATA}/notify.json`（插件数据目录，推荐）
2. `~/.claude/hooks/notify.json`（传统路径）

如果两个路径都不存在配置文件，使用路径 1 创建新配置。

## 渠道信息

### 短通知渠道（即时触达，秒级延迟）

| 渠道 | 默认延迟 | 必填字段 | 说明 |
|------|---------|---------|------|
| macos | 3s | 无（零配置） | macOS 系统通知，可选 `sound`（默认 Glass） |
| telegram | 5s | `bot_token`, `chat_id` | Telegram Bot 推送 |
| bark | 15s | `key` | Bark 推送，可选 `server`（默认 https://api.day.app） |
| pushover | 15s | `app_token`, `user_key` | Pushover 推送 |
| ntfy | 15s | `topic` | ntfy 推送，可选 `server`（默认 https://ntfy.sh） |
| gotify | 15s | `server`, `app_token` | Gotify 自建推送 |

### 长通知渠道（异步兜底，分钟级延迟）

| 渠道 | 默认延迟 | 必填字段 | 说明 |
|------|---------|---------|------|
| wechat | 300s | `webhook` | 企业微信群机器人 |
| feishu | 300s | `webhook` | 飞书群机器人 |
| dingtalk | 300s | `webhook` | 钉钉群机器人 |
| slack | 300s | `webhook` | Slack Incoming Webhook |
| discord | 300s | `webhook` | Discord Channel Webhook |

### 渠道凭证获取指引

- **Bark**: 安装 Bark App → 首页推送 URL `https://api.day.app/xxxxxxxx`，`xxxxxxxx` 即为 key
- **Telegram**: @BotFather 创建 Bot 获取 bot_token → 向 Bot 发消息 → 访问 `https://api.telegram.org/bot<TOKEN>/getUpdates` 获取 chat_id
- **Pushover**: 注册 pushover.net 获取 user_key → 创建 Application 获取 app_token
- **ntfy**: 安装 ntfy App → 订阅一个 topic → 填入 topic 名称
- **Gotify**: 自建 Gotify 服务 → 创建 Application 获取 app_token
- **企业微信**: 群聊 → 群机器人 → 添加 → 复制 Webhook URL
- **飞书**: 群设置 → 群机器人 → 自定义机器人 → 复制 Webhook URL
- **钉钉**: 群设置 → 智能群助手 → 自定义机器人（关键词模式）→ 复制 Webhook URL
- **Slack**: 创建 Slack App → Incoming Webhooks → Add New Webhook → 复制 URL
- **Discord**: 服务器设置 → 整合 → Webhooks → 新建 → 复制 URL

## AskUserQuestion 约束

**关键限制**：AskUserQuestion 每个问题最多 4 个选项（minItems=2, maxItems=4）。有 11 个渠道无法一次列全。

**应对策略**：
- 短通知 6 个渠道，分两轮：第一轮 macos/telegram/bark/pushover，第二轮 ntfy/gotify（2 个选项即可）
- 长通知 5 个渠道，分两轮：第一轮 wechat/feishu/dingtalk/slack，第二轮 discord（用 2 选项：启用/不启用）
- 使用 `multiSelect: true`，在 description 中标注 `[当前已启用]` 或 `[当前未启用]` 帮助用户判断
- 已启用的渠道不会因为用户未选中而自动禁用——只有在用户明确取消选择时才禁用

## 执行流程

### 第一步：读取现有配置

用 Bash 读取配置文件（先检查 `${CLAUDE_PLUGIN_DATA}/notify.json`，再检查 `~/.claude/hooks/notify.json`）。如果不存在，记住稍后需要创建新配置。解析每个渠道的 enabled 状态和凭证是否为占位值。

### 第二步：展示当前状态

向用户展示当前所有渠道的状态概览表格：

```
短通知渠道（即时触达）
  macos      ✅ 已启用   延迟 3s
  telegram   ❌ 未配置
  bark       ❌ 未配置
  pushover   ❌ 未配置
  ntfy       ❌ 未配置
  gotify     ❌ 未配置

长通知渠道（异步兜底）
  wechat     ✅ 已启用   延迟 300s
  feishu     ❌ 未配置
  dingtalk   ❌ 未配置
  slack      ❌ 未配置
  discord    ❌ 未配置
```

### 第三步：选择短通知渠道

**第一轮（4 个渠道）**：用 AskUserQuestion（multiSelect=true）让用户选择要启用的短通知渠道。

选项：macos、telegram、bark、pushover。每个选项的 description 中标注当前状态，如：
- label: "macos", description: "[当前已启用] macOS 系统通知，零配置"
- label: "telegram", description: "[当前未启用] Telegram Bot，需要 bot_token 和 chat_id"

**第二轮（2 个渠道）**：ntfy、gotify，同样 multiSelect=true，description 标注状态。

将两轮的选择结果合并。对比现有配置：
- 新选中的渠道 → 标记为待配置
- 取消选中的渠道 → 设为 enabled=false（保留凭证）
- 未变化的 → 保持不动

### 第四步：选择长通知渠道

同样分轮：

**第一轮**：wechat、feishu、dingtalk、slack（multiSelect=true）
**第二轮**：discord（2 选项：启用/不启用）

合并结果，同第三步逻辑。

### 第五步：配置渠道凭证（循环）

对所有新启用的或凭证仍为占位值的渠道，逐个引导配置：

1. 显示该渠道的凭证获取指引（从上方"渠道凭证获取指引"查找）
2. 用 AskUserQuestion 逐个请求必填字段值。用 preview 展示凭证格式示例。
3. 询问延迟时间（显示默认值，提供 2-3 个常用选项 + Other）
4. 可选：询问是否限制事件类型

每个渠道配置完成后，立即写入配置文件（避免丢失）。

然后用 AskUserQuestion 询问下一步：
- **配置下一个渠道**（如果还有待配置的）
- **修改已配置的渠道** — 让用户选一个已配置渠道重新编辑
- **完成配置**

如果用户选择"修改已配置的渠道"，显示该渠道当前配置值（凭证脱敏），让用户逐字段修改（留空保持不变）。修改完成后回到此步骤继续循环。

如果用户选择"完成配置"，进入下一步。

### 第六步：保存并测试

将最终配置写入配置文件。

**写入规则**：
- 如果原配置来自 `~/.claude/hooks/notify.json`，继续写入该路径
- 如果是新配置，写入 `${CLAUDE_PLUGIN_DATA}/notify.json`（先用 Bash mkdir -p 确保目录存在）
- 保持 JSON 格式化（缩进 2 空格）
- 不要丢失用户未修改的渠道配置
- 始终包含 `rate_limit` 字段

写入后用 AskUserQuestion 询问是否测试：
- **测试所有已启用渠道**
- **测试指定渠道**
- **跳过测试**

测试用 Bash 运行：
```bash
bash ${CLAUDE_PLUGIN_ROOT}/test_notify.sh <channel_name>
```

## 注意事项

- 所有交互使用 AskUserQuestion，不要假设用户的选择
- 展示凭证时注意脱敏（只显示前 4 位和后 4 位，中间用 *** 代替）
- 用中文与用户交互
- 每次修改后立即保存，避免中途丢失
- 如果 `$ARGUMENTS` 包含渠道名（如 `/cc-notify-hooks:config bark`），跳过渠道选择步骤，直接进入该渠道的凭证配置
- 占位值判断：凭证值包含 "your-" 前缀或等于示例模板中的默认值时，视为未配置
