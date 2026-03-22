# cc-notify-hooks

Claude Code 的分级推送通知系统。离开键盘后，按配置的延迟逐级提醒，回来操作即自动取消排队中的推送。

支持 **11 个通知渠道**，可作为 **Claude Code 插件** 或独立脚本使用。

## 支持的渠道

| 渠道 | 类型 | 默认延迟 | 说明 |
|------|------|---------|------|
| **macOS** | 系统通知 | 3s | 零配置，osascript 原生通知 |
| **Telegram** | Bot API | 5s | 个人/群组消息 |
| **Bark** | 推送服务 | 15s | iOS / macOS / Android |
| **Pushover** | 推送服务 | 15s | 跨平台推送 |
| **ntfy** | 推送服务 | 15s | 开源，支持自建 |
| **Gotify** | 推送服务 | 15s | 自建推送服务 |
| **企业微信** | Webhook | 5min | 群机器人 |
| **飞书** | Webhook | 5min | 群机器人 |
| **钉钉** | Webhook | 5min | 群机器人 |
| **Slack** | Webhook | 5min | Incoming Webhook |
| **Discord** | Webhook | 5min | Channel Webhook |

每个渠道的延迟可独立调整。只启用你需要的渠道，其余自动跳过。

## 工作原理

```
Claude Code 事件
    │
    ▼
notify.sh ── 清除旧 pending → 创建新 pending
    │
    ├─ 按 delay 排序所有已启用渠道
    │
    ├─ delay=3s  → pending 还在？ → macOS 系统通知
    ├─ delay=5s  → pending 还在？ → Telegram
    ├─ delay=15s → pending 还在？ → Bark / Pushover / ntfy / ...
    └─ delay=5m  → pending 还在？ → 企微 / 飞书 / Slack / ...

用户交互（发消息 / 点权限按钮）
    └─→ clear_pending.sh → 清除 pending → 后续推送全部取消
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

安装后，复制配置模板并编辑：

```bash
cp ~/.claude/plugins/cache/cc-notify-hooks/cc-notify-hooks/*/config/notify.example.json ~/.claude/hooks/notify.json
# 编辑 ~/.claude/hooks/notify.json，启用你需要的渠道并填入凭证
```

### 方式二：本地插件模式

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
claude --plugin-dir ./cc-notify-hooks
```

配置文件放在 `~/.claude/hooks/notify.json`（从 `config/notify.example.json` 复制修改）。

### 方式三：独立安装（无需插件）

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh
```

安装脚本会交互式引导你选择渠道、输入凭证，自动生成配置并合并 hooks。

安装后**重启 Claude Code** 使 hooks 生效。

### 验证

```bash
bash test_notify.sh              # 测试所有已启用渠道
bash test_notify.sh bark         # 测试单个渠道
bash test_notify.sh list         # 查看已启用渠道及延迟
bash test_notify.sh hook         # 模拟完整推送流程
```

## 配置

配置文件：`~/.claude/hooks/notify.json`

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
