# cc-notify-hooks

**Claude Code** 与 **Codex CLI** 的分级推送通知系统。支持 **11 个通知渠道**，可作为插件或独立脚本使用，两边共享同一份配置。

## 为什么需要分级通知？

Claude Code 和 Codex CLI 任务常常需要几秒到几十分钟不等。你不会一直盯着终端，但又需要在合适的时候回来操作。

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
Claude Code / Codex CLI 事件
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

### 方式一：Claude Code Marketplace（推荐 Claude 用户）

在 Claude Code 中执行：

```
/plugin marketplace add MarioZZJ/cc-notify-hooks
/plugin install cc-notify-hooks@cc-notify-hooks
```

安装后运行 `/reload-plugins` 刷新，然后执行 `/cc-notify-hooks:config` 启动交互式配置向导（见下方[配置](#配置)章节）。

### 方式二：Codex CLI Marketplace（推荐 Codex 用户）

仓库根目录的 `.agents/plugins/marketplace.json` 是 Codex marketplace，实际插件目录是 `plugins/cc-notify-hooks/`。在终端执行：

```bash
codex plugin marketplace add MarioZZJ/cc-notify-hooks --ref v2.2.2
codex plugin add cc-notify-hooks@cc-notify-hooks
```

启用 hooks（必需，Codex 默认关闭）：在 `~/.codex/config.toml` 添加：

```toml
[features]
codex_hooks = true
```

之后重启 Codex，或在新会话中使用插件。

注意：Codex 的 hook 命令运行目录是当前会话 `cwd`，不是插件根目录。`.codex-plugin/plugin.json` 只负责把 `hooks/codex-hooks.json` 作为生命周期配置打包进去；hook 命令不能写成 `./scripts/...`，否则在普通项目里会找不到脚本并报 `No such file or directory`。本插件的 Codex hook 会从 `~/.codex/plugins/cache/*/cc-notify-hooks/*/` 自动定位安装副本。

### 方式三：本地插件模式

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git

# Claude Code
claude --plugin-dir ./cc-notify-hooks/plugins/cc-notify-hooks

# Codex CLI: 见上文 Codex Marketplace 方式
```

### 方式四：独立安装（无需插件）

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh                  # 交互式选择 Claude Code / Codex
bash install.sh claude           # 直接装到 Claude Code
bash install.sh codex            # 直接装到 Codex CLI
```

安装脚本会交互式引导你选择渠道、输入凭证，自动生成配置：

- **Claude 分支**：写 `~/.claude/hooks/notify.json`，合并 hooks 到 `~/.claude/settings.json`
- **Codex 分支**：写 `~/.codex/cc-notify-hooks/notify.json`，合并 hooks 到 `~/.codex/hooks.json`，提示你启用 `codex_hooks`

**Claude 安装后运行 `/reload-plugins` 刷新；Codex 安装后重启 Codex 进程。**

### 验证

```bash
bash test_notify.sh              # 测试所有已启用渠道
bash test_notify.sh bark         # 测试单个渠道
bash test_notify.sh list         # 查看已启用渠道及延迟
bash test_notify.sh hook         # 模拟 Claude Code hook 流程
bash test_notify.sh codex        # 模拟 Codex CLI PermissionRequest 事件
bash test_notify.sh codex-plugin-hooks  # 验证 Codex 插件 hook 路径解析
bash test_notify.sh render       # 验证通知内容模板
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
curl -sL https://raw.githubusercontent.com/MarioZZJ/cc-notify-hooks/main/plugins/cc-notify-hooks/config/notify.example.json \
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

### Claude Code

| Hook | 触发时机 | 行为 |
|------|---------|------|
| Notification | 权限确认、等待输入等 | 分级推送 |
| Stop | Claude 回复结束 | 分级推送 |
| UserPromptSubmit | 用户发消息 | 清除 pending |
| PreToolUse | 用户点权限按钮 | 清除 pending |

### Codex CLI

| Hook | 触发时机 | 行为 |
|------|---------|------|
| PermissionRequest | Codex 请求授权时 | 分级推送 |
| Stop | Codex 回合结束 | 分级推送 |
| UserPromptSubmit | 用户发消息 | 清除 pending |
| PreToolUse | 工具调用前 | 清除 pending |

> Codex 没有 `Notification` 事件，使用 `PermissionRequest` 作为对应——只在真的需要授权时触发，不会被空闲提示干扰。

## 通知内容

通知标题使用实际 Agent 名，不再写死为 Claude：

| 场景 | 标题 | 正文 |
|------|------|------|
| Claude Code Notification idle_prompt | `Claude Code · 等待响应` | `[项目名] 通知消息` |
| Codex PermissionRequest | `Codex · 需要确认` | `[项目名] 权限提示` |
| Stop | `{Agent} · 任务完成` | `[项目名] last_assistant_message 首个非空行` |

模板只依赖两边共同字段：`cwd`、`hook_event_name`、`model`、`message/prompt`、`last_assistant_message`。`permission_mode`、`notification_type`、`tool_name` 等字段只作为可选补充，不作为跨平台核心依赖。

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
│   ├── plugin.json -> ../plugins/cc-notify-hooks/.claude-plugin/plugin.json
│   └── marketplace.json     # Claude Code marketplace（指向 plugins/cc-notify-hooks）
├── .codex-plugin/
│   └── plugin.json -> ../plugins/cc-notify-hooks/.codex-plugin/plugin.json
├── .agents/plugins/
│   └── marketplace.json     # Codex CLI marketplace（指向 plugins/cc-notify-hooks）
├── plugins/cc-notify-hooks/ # 真实插件根目录，Claude/Codex 都从这里安装
│   ├── .claude-plugin/plugin.json
│   ├── .codex-plugin/plugin.json
│   ├── skills/config/SKILL.md
│   ├── hooks/
│   │   ├── hooks.json
│   │   └── codex-hooks.json
│   ├── scripts/
│   │   ├── notify.sh
│   │   ├── clear_pending.sh
│   │   └── channels/
│   ├── config/notify.example.json
│   └── test_notify.sh
├── skills -> plugins/cc-notify-hooks/skills
├── hooks -> plugins/cc-notify-hooks/hooks
├── scripts -> plugins/cc-notify-hooks/scripts
├── config -> plugins/cc-notify-hooks/config
├── install.sh               # 独立安装入口（路由）
├── install/
│   ├── claude.sh            # Claude Code 安装分支
│   └── codex.sh             # Codex CLI 安装分支
└── test_notify.sh -> plugins/cc-notify-hooks/test_notify.sh
```

调试日志：`/tmp/claude-hooks-debug.log`

## 卸载

**Claude Code 插件**：在 Claude Code 中 `/plugin` 管理。

**Codex CLI 插件**：在 Codex 中 `/plugin` 管理。

**独立安装（Claude）**：
```bash
rm -rf ~/.claude/hooks/scripts ~/.claude/hooks/notify.json ~/.claude/hooks/state
# 手动编辑 ~/.claude/settings.json 移除相关 hooks
```

**独立安装（Codex）**：
```bash
rm -rf ~/.codex/cc-notify-hooks
# 手动编辑 ~/.codex/hooks.json 移除相关事件，可选关闭 codex_hooks
```

## License

MIT
