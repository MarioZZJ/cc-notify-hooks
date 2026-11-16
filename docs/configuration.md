# 通知配置

[← 项目首页](../README.md) · [安装指南](getting-started.md) · [开发与排错](development.md)

每个渠道独立设置 `enabled`、`delay` 和 `events`。只启用需要的渠道，填写对应凭据即可。

## 交互式配置

Claude Code 中运行：

```text
/cc-notify-hooks:config
```

ChatGPT Codex 插件也提供 `config` 技能及 setup 入口。向导会显示已有配置状态，帮助选择短通知与长通知渠道、填写凭据、调整延迟，并提供连通性测试。DeepSeek Harness 与 Magpie 通常直接编辑配置文件。

## 配置文件位置

| 安装环境 | 默认配置位置 |
| --- | --- |
| ChatGPT Codex 插件 | `${PLUGIN_DATA}/notify.json` |
| Claude Code 插件 | `${CLAUDE_PLUGIN_DATA}/notify.json` |
| Magpie | `~/.config/cc-notify-hooks/notify.json` |
| ChatGPT Codex 独立安装 | `${CODEX_HOME:-~/.codex}/cc-notify-hooks/notify.json` |
| DeepSeek Harness | `${DSH_HOME:-~/.dsh}/cc-notify-hooks/notify.json` |
| Claude Code 独立安装 | `~/.claude/hooks/notify.json` |

插件数据目录由宿主提供。优先通过配置技能写入实际数据目录，或编辑已经使用的配置文件；不要把凭据写进随升级替换的插件缓存。

运行时按以下顺序选择第一个已存在的配置文件：

1. `CC_NOTIFY_CONFIG` 指定的路径。
2. `${PLUGIN_DATA}/notify.json`。
3. `${CLAUDE_PLUGIN_DATA}/notify.json`。
4. `~/.config/cc-notify-hooks/notify.json`。
5. `${CODEX_HOME:-~/.codex}/cc-notify-hooks/notify.json`。
6. `${REASONIX_HOME:-~/.reasonix}/cc-notify-hooks/notify.json`，兼容已有 Reasonix 配置。
7. `${DSH_HOME:-~/.dsh}/cc-notify-hooks/notify.json`。
8. `~/.claude/hooks/notify.json`。

独立安装器会将自己的配置路径绑定到 hook 命令。DeepSeek Harness 的 `configFile` / `stateDir` 与 Magpie 的 `configPath` / `stateDir` 设置见[安装指南](getting-started.md)。

### 手动创建配置

从[完整配置模板](../plugins/cc-notify-hooks/config/notify.example.json)复制到当前安装使用的位置。下面以 **Claude Code 独立安装**的默认位置为例：

```bash
mkdir -p ~/.claude/hooks
curl -fL https://raw.githubusercontent.com/MarioZZJ/cc-notify-hooks/main/plugins/cc-notify-hooks/config/notify.example.json \
  -o ~/.claude/hooks/notify.json
```

已克隆仓库时，也可在仓库根目录执行：

```bash
mkdir -p ~/.claude/hooks
cp config/notify.example.json ~/.claude/hooks/notify.json
```

这些命令用于新建配置。已有配置时直接编辑原文件，以保留渠道凭据与自定义设置。

## 默认行为与示例

模板默认只启用 macOS，延迟 3 秒，订阅 `notification`。其他 10 个渠道默认关闭。需要正常回合结束提醒时，为所需渠道添加 `stop`。

以下示例启用桌面通知、Bark 与 Telegram：

```json
{
  "channels": {
    "macos": {
      "enabled": true,
      "delay": 3,
      "events": ["notification", "stop"]
    },
    "bark": {
      "enabled": true,
      "delay": 15,
      "key": "your-key",
      "server": "https://api.day.app"
    },
    "telegram": {
      "enabled": true,
      "delay": 5,
      "bot_token": "123:ABC",
      "chat_id": "123456"
    }
  },
  "rate_limit": 10
}
```

桌面与飞书搭配的示例见 [README 配置](../README.md#配置)。将示例凭据替换为自己的值后，再验证所启用渠道的送达。

## 字段说明

| 字段 | 含义 |
| --- | --- |
| `channels.<name>.enabled` | 只有 `true` 的渠道会加入发送队列 |
| `channels.<name>.delay` | 插件收到事件后的等待秒数；各渠道独立计算 |
| `channels.<name>.events` | 可选的事件类型数组；省略时不做类型筛选，当前正常入口使用 `notification` 与 `stop` |
| `channels.<name>.format` | 长通知格式：飞书默认 `card`，企业微信／钉钉／Slack 默认 `markdown`，Discord 默认 `embed`；可设为 `text` |
| `rate_limit` | 全局去重时间窗口，默认 10 秒；按会话与事件类别隔离，结构化问题及带调用 ID 的审批使用精确去重 |
| `key`、`webhook`、`token` 等 | 渠道所需凭据，具体字段见下表 |

### 事件类型

| 配置值 | 对应通知 |
| --- | --- |
| `notification` | 等待确认、结构化提问、异常；Magpie 的模型响应完成与模型请求异常也使用此值 |
| `stop` | Claude Code、ChatGPT Codex、DeepSeek Harness 的正常回合结束 |

Magpie 的完成消息使用 `notification`。为 Magpie 只设置 `events: ["stop"]` 不会收到网关响应消息。

延迟从插件接收到宿主事件开始，宿主自身等待时间另计。长通知渠道默认 300 秒；插件不根据任务已经运行多久自动选择渠道。

## 渠道与默认值

| 渠道 | 配置名称 | 默认延迟 | 默认格式或方式 | 主要字段 |
| --- | --- | --- | --- | --- |
| macOS | `macos` | 3 秒 | 系统通知 | 可选 `sound`，默认 `Glass` |
| Telegram | `telegram` | 5 秒 | Bot 消息 | `bot_token`、`chat_id` |
| Bark | `bark` | 15 秒 | 推送服务 | `key`、可选 `server` / `sound` |
| Pushover | `pushover` | 15 秒 | 跨平台推送 | `app_token`、`user_key` |
| ntfy | `ntfy` | 15 秒 | 推送服务，可自建 | `topic`、可选 `server` |
| Gotify | `gotify` | 15 秒 | 自建推送服务 | `server`、`app_token` |
| 企业微信 | `wechat` | 300 秒 | Markdown | `webhook`、可选 `format` |
| 飞书 | `feishu` | 300 秒 | 消息卡片 | `webhook`、可选 `format` |
| 钉钉 | `dingtalk` | 300 秒 | Markdown | `webhook`、可选 `format` |
| Slack | `slack` | 300 秒 | Markdown | `webhook`、可选 `format` |
| Discord | `discord` | 300 秒 | Embed | `webhook`、可选 `format` |

Bark 的默认 `server` 为 `https://api.day.app`，ntfy 为 `https://ntfy.sh`。配置模板中的凭据均为占位值。

## 渠道凭据

### macOS

使用系统 `osascript`，无需服务端凭据。可通过 `sound` 设置提示音。脚本只能在运行它的 Mac 上生成原生通知；未找到配置文件时，macOS 对 `notification` 事件提供 3 秒默认提醒，其他平台不发送。

### Bark

1. 安装 [Bark App](https://github.com/Finb/Bark)。
2. 推送 URL 如 `https://api.day.app/xxxxxxxx`，其中 `xxxxxxxx` 是 `key`。
3. 自建服务时设置 `server`。

### Telegram

1. 通过 [@BotFather](https://t.me/BotFather) 创建 Bot，获取 `bot_token`。
2. 向 Bot 发送一条消息。
3. 查看 `https://api.telegram.org/bot<TOKEN>/getUpdates` 获取 `chat_id`。

### Pushover

1. 在 [pushover.net](https://pushover.net) 注册，获取 `user_key`。
2. 创建 Application，获取 `app_token`。

### ntfy

1. 在 [ntfy](https://ntfy.sh) 客户端订阅一个 topic。
2. 填写 `topic`；使用自建服务时设置 `server`。

### Gotify

1. 部署 [Gotify](https://gotify.net) 服务。
2. 创建 Application，获取 `app_token`。
3. 填写 `server` 与 `app_token`。

### 企业微信

在群聊的「⋯」→ 群机器人中添加机器人，将 Webhook 地址填入 `webhook`。

### 飞书

在群设置 → 群机器人 → 添加机器人 → 自定义机器人中创建入口，将 Webhook 地址填入 `webhook`。

### 钉钉

在群设置 → 智能群助手 → 添加机器人中创建自定义机器人，使用关键词模式，将 Webhook 地址填入 `webhook`。关键词需实际出现在通知内容中，可使用项目名。

### Slack

1. 创建 [Slack App](https://api.slack.com/apps)，启用 **Incoming Webhooks**。
2. 选择 **Add New Webhook to Workspace** 和接收频道。
3. 将 Webhook URL 填入 `webhook`。

### Discord

在服务器设置 → 整合 → Webhooks 中创建入口，选择频道，将 Webhook URL 填入 `webhook`。

## 事件覆盖与取消

| 入口 | 发出通知 | 清理待发通知的时机 |
| --- | --- | --- |
| Claude Code | `Notification`、`AskUserQuestion`、`Stop`、`StopFailure` | 新输入、普通工具开始、工具成功／失败、提问结束、`SessionEnd` |
| ChatGPT Codex | `PermissionRequest`、`request_user_input`、`Stop` | 新输入、普通工具开始、工具完成、提问结束、`Interrupt`、`SessionEnd` |
| DeepSeek Harness | 审批等待、结构化提问、正常回合结束、错误／阻止／输出上限 | 审批决定、提问结束或取消、新输入、新回合、Agent 销毁、插件卸载 |
| Magpie | 可识别的完整文本响应、请求错误 | 同会话下一次网关请求 |

取消作用于尚未发送的通知。已送达的消息保留；其他会话继续独立排队。查看通知本身不会生成宿主后续活动信号。

### Claude Code 的 hooks

| Hook | 时机与作用 |
| --- | --- |
| `Notification` | 权限确认、等待输入等宿主通知进入分级队列 |
| `PreToolUse` | 工具调用前；`AskUserQuestion` 排队提问通知，普通工具清理当前会话待发通知 |
| `Stop` / `StopFailure` | 回复结束／异常提醒 |
| `UserPromptSubmit` | 用户提交新输入，清理当前会话队列 |
| `PostToolUse` / `PostToolUseFailure` | 工具结束时清理相关通知；提问结束另行定向清理 |
| `SessionEnd` | 会话结束，清理队列 |

`PreToolUse` 发生在权限确认前，不能解释为用户已经点击权限按钮。Claude Code 的 `permission_prompt` 通常先由宿主等待约 6 秒，`idle_prompt` 通常约 60 秒，再进入插件的渠道延迟。

### ChatGPT Codex 的 hooks

| Hook | 时机与作用 |
| --- | --- |
| `PermissionRequest` | 审批请求进入分级队列 |
| `PreToolUse` | `request_user_input` 调用前排队“需要回复”通知；普通工具清理当前会话队列 |
| `PostToolUse` | 工具结束后清理相关提醒；`request_user_input` 结束后清理该会话的待发输入通知 |
| `Stop` | 正常回合结束提醒 |
| `UserPromptSubmit` | 用户提交新输入，清理队列 |
| `Interrupt` / `SessionEnd` | 中断或会话结束，清理队列 |

`request_user_input` 的等待状态通过工具 hooks 识别，复用 `notification` 渠道规则。`PermissionRequest` 可能由自动审阅或人工审批触发；当前 payload 不能精确区分人工是否正在等待，见 [#3](https://github.com/MarioZZJ/cc-notify-hooks/issues/3)。Claude Code 与 ChatGPT Codex 均不能保证在点击审批按钮的瞬间取消待发通知。

DeepSeek Harness 的原生审批／提问事件、最终回合结束原因，以及 Magpie 的模型响应判定详见[兼容性说明](compatibility.md)。

## 通知内容

插件先归一事件字段，再按渠道渲染。通知中的 Agent 名称与实现保持一致，例如 ChatGPT Codex 显示为 `Codex`，DeepSeek Harness 显示为 `dsh`。

| 场景 | 标题示例 |
| --- | --- |
| Claude Code 的 `idle_prompt` | `Claude Code · 等待响应 ⏳` |
| 审批请求 | `Codex · 需要确认 🔔` |
| 结构化提问 | `Codex · 需要回复 🔔` |
| 原生 Agent 正常回合结束 | `{Agent} · 任务完成 ✅` |
| 原生 Agent 错误 | `{Agent} · 任务异常 ⚠️` |
| Magpie 完整文本响应 | `Magpie · 模型响应完成 💬` |
| Magpie 请求错误 | `Magpie · 模型请求异常 ⚠️` |
| 其他未知事件 | `{Agent} · 异常 ⚠️` |

短通知正文：

```text
[项目名] summary_short · tool_name
```

`tool_name` 有值才显示，`permission_mode` 不进入通知正文。结构化提问的短正文另含问题数和短 Session ID：

```text
[项目名] 首个问题摘要 · 2 个问题 · Session 019eabcd
```

长通知的字段结构：

```text
summary_short

项目: project
事件: hook_event_name
工具: tool_name
Session: session_short

model · cwd · hostname
```

工具、会话和尾部定位字段按是否可用显示。普通通知的 Session 取前 8 个字符；等待输入的长通知使用完整 Session ID，并补充问题数、首题选项。飞书默认使用消息卡片，企业微信、钉钉、Slack 使用近似 Markdown，Discord 使用 embed。

`summary_short` 来自 `message/prompt`、首个结构化问题或 `last_assistant_message` 的首个非空行，最长保留 120 字。通知提供摘要与定位信息，完整结果仍在原会话中查看。
