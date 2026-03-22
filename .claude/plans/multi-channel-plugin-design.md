# cc-notify-hooks v2：多 Channel + 插件化设计

**日期**：2026-03-22
**状态**：已批准

## 概述

将 cc-notify-hooks 从 3 channel 的 shell 脚本重构为支持 11 个通知渠道的 Claude Code 插件，采用 JSON 配置、模块化 channel 架构、预设延迟可覆盖的分级推送模型。

## 决策记录

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 分级模型 | 预设默认 + 可覆盖 delay | 零配置可用，进阶用户可调 |
| 配置格式 | JSON | 结构化且 jq 已是必需依赖，零新增依赖 |
| 插件策略 | 直接按插件结构开发 | 用 `claude --plugin-dir` 测试，一步到位 |
| 架构模式 | Channel 模块化（每 channel 一个文件） | 职责单一，加 channel 不动主逻辑 |
| Channel 范围 | v1 全部 11 个 | 每个 channel 本质就是一个 curl，架构设计好后加就是填模板 |

## 支持的 Channel

| Channel | 类型 | 默认 delay | 默认 events | 凭证字段 |
|---------|------|-----------|-------------|---------|
| macos | 本地 osascript | 3s | notification | 无（零配置） |
| bark | 推送服务 | 15s | notification, stop | key, server |
| telegram | Bot API | 5s | notification, stop | bot_token, chat_id |
| pushover | 推送服务 | 15s | notification, stop | app_token, user_key |
| ntfy | 推送服务 | 15s | notification, stop | topic, server |
| gotify | 自建推送 | 15s | notification, stop | server, app_token |
| wechat | Webhook | 300s | notification, stop | webhook |
| feishu | Webhook | 300s | notification, stop | webhook |
| dingtalk | Webhook | 300s | notification, stop | webhook |
| slack | Webhook | 300s | notification, stop | webhook |
| discord | Webhook | 300s | notification, stop | webhook |

## 插件目录结构

```
cc-notify-hooks/
├── .claude-plugin/
│   └── plugin.json              # 插件清单
├── hooks/
│   └── hooks.json               # hook 事件定义
├── scripts/
│   ├── notify.sh                # 主调度器
│   ├── clear_pending.sh         # 用户交互清除 pending
│   └── channels/                # 每个 channel 一个文件
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
│   └── notify.example.json      # 配置模板
├── install.sh                   # 非插件用户的安装入口
├── test_notify.sh               # 连通性测试
├── README.md
└── LICENSE
```

## JSON 配置结构

位置优先级：`${CLAUDE_PLUGIN_DATA}/notify.json` → `~/.claude/hooks/notify.json` → 仅 macOS 通知

```json
{
  "channels": {
    "macos": {
      "enabled": true,
      "delay": 3,
      "sound": "Glass",
      "events": ["notification"]
    },
    "bark": {
      "enabled": true,
      "delay": 15,
      "key": "your-bark-key",
      "server": "https://api.day.app"
    },
    "telegram": {
      "enabled": false,
      "delay": 5,
      "bot_token": "123456:ABC-DEF...",
      "chat_id": "123456789"
    },
    "pushover": {
      "enabled": false,
      "delay": 15,
      "app_token": "xxx",
      "user_key": "xxx"
    },
    "ntfy": {
      "enabled": false,
      "delay": 15,
      "topic": "my-claude",
      "server": "https://ntfy.sh"
    },
    "gotify": {
      "enabled": false,
      "delay": 15,
      "server": "https://gotify.example.com",
      "app_token": "xxx"
    },
    "wechat": {
      "enabled": false,
      "delay": 300,
      "webhook": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
    },
    "feishu": {
      "enabled": false,
      "delay": 300,
      "webhook": "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"
    },
    "dingtalk": {
      "enabled": false,
      "delay": 300,
      "webhook": "https://oapi.dingtalk.com/robot/send?access_token=xxx"
    },
    "slack": {
      "enabled": false,
      "delay": 300,
      "webhook": "https://hooks.slack.com/services/T.../B.../xxx"
    },
    "discord": {
      "enabled": false,
      "delay": 300,
      "webhook": "https://discord.com/api/webhooks/xxx/xxx"
    }
  },
  "rate_limit": 10
}
```

### 字段说明

- **enabled**：显式开关，`false` 或缺失则跳过
- **delay**：秒，每个 channel 可独立调整（预设 + 可覆盖）
- **events**：可选，默认 `["notification", "stop"]`，macOS 默认只 `["notification"]`
- **channel 专属字段**：每个 channel 只有自己需要的凭证，无冗余

## Channel 脚本接口

统一函数签名：

```bash
# send_<channel_name> <title> <body> <channel_config_json>
send_bark() {
    local title="$1" body="$2" config="$3"
    local key=$(echo "$config" | jq -r '.key')
    local server=$(echo "$config" | jq -r '.server // "https://api.day.app"')
    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg k "$key" --arg t "$title" --arg b "$body" \
            '{device_key:$k, title:$t, body:$b, level:"timeSensitive", group:"claude-code"}')" \
        "${server}/push" >/dev/null 2>&1 || true
}
```

**约定**：
- 函数名 `send_<name>` 与配置中的 key 一致
- 参数：title、body、该 channel 的 JSON config 对象
- 不做 pending 检查、不做 sleep（纯发送）
- 失败不致命（`|| true`）

## Pipeline 编排

```
notify.sh 主流程：
1. 读取配置 JSON
2. stdin 读取事件 JSON → 解析字段
3. 过滤规则：子智能体 / 循环保护 / /exit / rate limit
4. 构造 title + body
5. 创建 pending 文件
6. 构建发送队列：
   enabled=true + events 匹配 → 按 delay 升序排序
   → [(macos,3), (telegram,5), (bark,15), (ntfy,15), (wechat,300), ...]
7. 后台子 shell：
   elapsed=0
   for (channel, delay) in sorted_queue:
       wait = delay - elapsed
       sleep $wait
       if pending 不存在: exit
       source channels/<channel>.sh
       send_<channel> "$title" "$body" "$channel_config"
       elapsed = delay
   rm pending
```

**关键设计**：
- 同 delay 的 channel 在同一轮依次发送，不额外 sleep
- pending 检查在每个 delay 节点做一次（同 delay 的一批要么全发要么全跳）
- 整个 pipeline 是一个后台子 shell（`(...) &`），不阻塞 hook 返回

## Hook 配置（hooks/hooks.json）

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh notification",
          "timeout": 5
        }]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh stop",
          "timeout": 5
        }]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/clear_pending.sh",
          "timeout": 3
        }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/clear_pending.sh",
          "timeout": 3
        }]
      }
    ]
  }
}
```

## install.sh 改造

```
[1/4] 检查依赖（jq, curl）
[2/4] 选择启用的 channel
      → 列出所有 channel，用户输入编号多选
      → 对每个启用的 channel 提示输入凭证
      → 已有配置时显示当前值作为默认
[3/4] 安装脚本
      → 复制 scripts/（含 channels/）到 ~/.claude/hooks/
      → 生成 ~/.claude/hooks/notify.json
[4/4] 配置 hooks
      → hooks.json 中 ${CLAUDE_PLUGIN_ROOT} 替换为 ~/.claude/hooks
      → 合并到 ~/.claude/settings.json
```

## test_notify.sh 改造

```bash
bash test_notify.sh              # 测试所有已启用 channel
bash test_notify.sh bark         # 测试单个 channel
bash test_notify.sh hook         # 模拟完整 pipeline
bash test_notify.sh list         # 列出已启用 channel 及 delay
```

## 过滤规则（不变）

- 子智能体：agent_id 非空 → 跳过
- Stop 循环保护：stop_hook_active=true → 跳过
- /exit 静默：exiting 标记存在 → 跳过
- Rate Limiting：同类事件 rate_limit 秒内只推一次

## 迁移兼容

- v1 用户运行新 install.sh 时，检测到旧 `notify.conf` 自动迁移为 `notify.json`
- 环境变量（BARK_KEY 等）不再作为配置来源，仅 JSON 配置文件
- macOS 用户无配置文件时仍然零配置可用（fallback 行为）

## 各 Channel API 参考

### Bark
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"device_key":"KEY","title":"T","body":"B","level":"timeSensitive","group":"claude-code"}' \
  "https://api.day.app/push"
```

### Telegram
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"chat_id":"CHAT_ID","text":"T\nB","parse_mode":"HTML"}' \
  "https://api.telegram.org/botTOKEN/sendMessage"
```

### 企业微信
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"msgtype":"text","text":{"content":"T\nB"}}' \
  "WEBHOOK_URL"
```

### 飞书
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"msg_type":"text","content":{"text":"T\nB"}}' \
  "WEBHOOK_URL"
```

### 钉钉
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"msgtype":"text","text":{"content":"T\nB"}}' \
  "WEBHOOK_URL"
```

### Slack
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"text":"*T*\nB"}' \
  "WEBHOOK_URL"
```

### Discord
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"content":"**T**\nB"}' \
  "WEBHOOK_URL"
```

### Pushover
```bash
curl -sf --max-time 10 \
  -d "token=APP_TOKEN&user=USER_KEY&title=T&message=B" \
  "https://api.pushover.net/1/messages.json"
```

### ntfy
```bash
curl -sf --max-time 10 -H "Title: T" -H "Priority: 4" \
  -d "B" \
  "https://ntfy.sh/TOPIC"
```

### Gotify
```bash
curl -sf --max-time 10 -H "Content-Type: application/json" \
  -d '{"title":"T","message":"B","priority":5}' \
  "https://gotify.example.com/message?token=APP_TOKEN"
```
