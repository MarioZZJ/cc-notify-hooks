# cc-notify-hooks

Claude Code 的分级推送通知系统。支持 **11 个通知渠道**，可作为 **Claude Code 插件** 或独立脚本使用。

## 为什么需要分级通知？

Claude Code 任务常常需要几秒到几十分钟不等。你不会一直盯着终端，但又需要在合适的时候回来操作。

**cc-notify-hooks 将通知分为两级**：

**短通知（秒级）** — 你可能只是切到了浏览器或聊天窗口。系统通知、手机推送这类**即时触达**的渠道会在几秒内提醒你"Claude 需要你"。如果你看到通知并回来操作了，后续推送自动取消——不会再打扰你。

**长通知（分钟级）** — 你可能离开了电脑、在开会、甚至不在手机旁。企业微信群、飞书群、Slack 频道这类**团队/异步渠道**会在几分钟后兜底通知。即使你错过了短通知，最终也能从工作沟通工具里看到任务状态。

**核心机制**：每次推送前检查用户是否已响应（pending 文件是否还在）。用户一旦回来操作，所有排队中的推送自动作废。短通知解决了问题，长通知就不会再发。

## 支持的渠道

### 短通知渠道（即时触达）

适合切屏、短暂离开的场景。

| 渠道 | 默认延迟 | 说明 |
|------|---------|------|
| **macOS** | 3s | 零配置，系统原生通知 |
| **Telegram** | 5s | Bot 消息，手机即时推送 |
| **Bark** | 15s | iOS / macOS / Android 推送 |
| **Pushover** | 15s | 跨平台推送服务 |
| **ntfy** | 15s | 开源推送，支持自建 |
| **Gotify** | 15s | 自建推送服务 |

### 长通知渠道（异步兜底）

适合离开电脑、开会、或需要团队可见的场景。

| 渠道 | 默认延迟 | 说明 |
|------|---------|------|
| **企业微信** | 5min | 群机器人 Webhook |
| **飞书** | 5min | 群机器人 Webhook |
| **钉钉** | 5min | 群机器人 Webhook |
| **Slack** | 5min | Incoming Webhook |
| **Discord** | 5min | Channel Webhook |

每个渠道的延迟可独立调整。只启用你需要的渠道，其余自动跳过。

## 工作原理

```
Claude Code 事件
    │
    ▼
notify.sh ── 清除旧 pending → 创建新 pending
    │
    │  ┌── 短通知 ──────────────────────────────────┐
    ├─ │ 3s  → pending 还在？ → macOS 系统通知      │
    ├─ │ 5s  → pending 还在？ → Telegram             │
    ├─ │ 15s → pending 还在？ → Bark / ntfy / ...    │
    │  └────────────────────────────────────────────┘
    │  ┌── 长通知 ──────────────────────────────────┐
    └─ │ 5m  → pending 还在？ → 企微 / 飞书 / Slack │
       └────────────────────────────────────────────┘

用户回来操作（发消息 / 点权限按钮）
    └─→ clear_pending.sh → 清除 pending → 后续推送全部取消
         （短通知解决了，长通知就不发了）
```

## 安装

### 依赖

- **jq** — 解析 JSON（`brew install jq` / `apt install jq`）
- **curl** — 发送推送（通常已预装）

### 方式一：从 Marketplace 安装（推荐）

在 Claude Code 中执行：

```
/plugin marketplace add MarioZZJ/cc-notify-hooks
/plugin install cc-notify-hooks@cc-notify-hooks
```

安装后运行 `/reload-plugins` 刷新，然后执行 `/cc-notify-hooks:config` 启动交互式配置向导（见下方[配置](#配置)章节）。

### 方式二：本地插件模式

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
claude --plugin-dir ./cc-notify-hooks
```

### 方式三：独立安装（无需插件）

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh
```

安装脚本会交互式引导你选择渠道、输入凭证，自动生成配置并合并 hooks。

**安装后运行 `/reload-plugins` 刷新插件，即可开始使用。**

### 验证

```bash
bash test_notify.sh              # 测试所有已启用渠道
bash test_notify.sh bark         # 测试单个渠道
bash test_notify.sh list         # 查看已启用渠道及延迟
bash test_notify.sh hook         # 模拟完整推送流程
```

## 配置

### 方式一：交互式配置（推荐）

在 Claude Code 中运行：

```
/cc-notify-hooks:config
```

配置向导会引导你：
1. 选择要启用的**短通知渠道**（macOS、Telegram、Bark 等）
2. 选择要启用的**长通知渠道**（企业微信、飞书、Slack 等）
3. 逐个输入渠道凭证，附带获取指引
4. 调整延迟时间
5. 测试渠道连通性

已有配置的渠道会标注当前状态，支持随时修改。

### 方式二：手动编辑配置文件

创建配置文件 `~/.claude/hooks/notify.json`，可从模板复制后编辑：

```bash
# marketplace 安装：从项目仓库获取模板
curl -sL https://raw.githubusercontent.com/MarioZZJ/cc-notify-hooks/main/config/notify.example.json \
  -o ~/.claude/hooks/notify.json

# 本地 clone：直接复制
cp config/notify.example.json ~/.claude/hooks/notify.json
```

然后编辑配置文件，将你需要的渠道设为 `"enabled": true` 并填入凭证：

```json
{
  "channels": {
    "macos": { "enabled": true, "delay": 3, "events": ["notification"] },
    "bark":  { "enabled": true, "delay": 15, "key": "your-key", "server": "https://api.day.app" },
    "telegram": { "enabled": true, "delay": 5, "bot_token": "123:ABC", "chat_id": "123456" }
  },
  "rate_limit": 10
}
```

完整配置模板见 [`config/notify.example.json`](config/notify.example.json)。

### 字段说明

| 字段 | 说明 |
|------|------|
| `enabled` | 是否启用该渠道 |
| `delay` | 推送延迟（秒），可自由调整 |
| `events` | 可选，响应的事件类型，默认 `["notification", "stop"]` |
| 其他字段 | 各渠道的凭证（key、webhook、token 等） |

### 各渠道凭证

<details>
<summary><b>Bark</b></summary>

1. 安装 [Bark App](https://github.com/Finb/Bark)
2. 首页推送 URL `https://api.day.app/xxxxxxxx`，`xxxxxxxx` 即为 `key`
3. 自建服务器设置 `server` 字段
</details>

<details>
<summary><b>Telegram</b></summary>

1. 在 Telegram 中找 [@BotFather](https://t.me/BotFather)，创建 Bot，获取 `bot_token`
2. 向你的 Bot 发一条消息
3. 访问 `https://api.telegram.org/bot<TOKEN>/getUpdates` 获取 `chat_id`
</details>

<details>
<summary><b>Pushover</b></summary>

1. 注册 [pushover.net](https://pushover.net)，获取 `user_key`
2. 创建 Application，获取 `app_token`
</details>

<details>
<summary><b>ntfy</b></summary>

1. 安装 [ntfy App](https://ntfy.sh)，订阅一个 topic
2. 配置 `topic` 字段，自建服务器设置 `server`
</details>

<details>
<summary><b>Gotify</b></summary>

1. 自建 [Gotify](https://gotify.net) 服务
2. 创建 Application，获取 `app_token`
3. 配置 `server` 和 `app_token`
</details>

<details>
<summary><b>企业微信</b></summary>

1. 群聊 → 右上角「⋯」→ 群机器人 → 添加 → 新创建
2. 复制 Webhook 地址到 `webhook` 字段
</details>

<details>
<summary><b>飞书</b></summary>

1. 群设置 → 群机器人 → 添加机器人 → 自定义机器人
2. 复制 Webhook 地址到 `webhook` 字段
</details>

<details>
<summary><b>钉钉</b></summary>

1. 群设置 → 智能群助手 → 添加机器人 → 自定义（关键词模式）
2. 复制 Webhook 地址到 `webhook` 字段
3. 关键词需包含在通知内容中（项目名通常可满足）
</details>

<details>
<summary><b>Slack</b></summary>

1. 创建 [Slack App](https://api.slack.com/apps) → Incoming Webhooks → 启用
2. Add New Webhook to Workspace → 选择频道
3. 复制 Webhook URL 到 `webhook` 字段
</details>

<details>
<summary><b>Discord</b></summary>

1. 服务器设置 → 整合 → Webhooks → 新建
2. 选择频道，复制 Webhook URL 到 `webhook` 字段
</details>

## 监听事件

| Hook | 触发时机 | 行为 |
|------|---------|------|
| Notification | 权限确认、等待输入等 | 分级推送 |
| Stop | Claude 回复结束 | 分级推送 |
| UserPromptSubmit | 用户发消息 | 清除 pending |
| PreToolUse | 用户点权限按钮 | 清除 pending |

## 过滤规则

| 规则 | 说明 |
|------|------|
| 子智能体过滤 | `agent_id` 非空时跳过 |
| Stop 循环保护 | `stop_hook_active=true` 时跳过 |
| `/exit` 静默 | 后续 Stop 事件不推送 |
| Rate Limiting | 同类事件默认 10 秒内只推一次 |

## 文件结构

```
cc-notify-hooks/
├── .claude-plugin/
│   └── plugin.json          # Claude Code 插件清单
├── skills/
│   └── config/
│       └── SKILL.md         # 交互式配置向导（/cc-notify-hooks:config）
├── hooks/
│   └── hooks.json           # Hook 事件定义
├── scripts/
│   ├── notify.sh            # 主调度器
│   ├── clear_pending.sh     # 清除 pending
│   └── channels/            # 渠道脚本（每个 ~15-25 行）
│       ├── macos.sh
│       ├── bark.sh
│       ├── telegram.sh
│       ├── wechat.sh
│       ├── feishu.sh
│       ├── dingtalk.sh
│       ├── slack.sh
│       ├── discord.sh
│       ├── pushover.sh
│       ├── ntfy.sh
│       └── gotify.sh
├── config/
│   └── notify.example.json  # 配置模板
├── install.sh               # 独立安装脚本
└── test_notify.sh           # 连通性测试
```

调试日志：`/tmp/claude-hooks-debug.log`

## 卸载

**插件模式**：在 Claude Code 中 `/plugin` 管理。

**独立安装**：
```bash
rm -rf ~/.claude/hooks/scripts ~/.claude/hooks/notify.json ~/.claude/hooks/state
# 手动编辑 ~/.claude/settings.json 移除相关 hooks
```

## License

MIT
