# cc-notify-hooks

<img src="plugins/cc-notify-hooks/assets/icon.png" alt="cc-notify-hooks" width="96" height="96">

当前版本：[v2.5.0](https://github.com/MarioZZJ/cc-notify-hooks/releases/tag/v2.5.0)。

面向 **Claude Code、Codex CLI、DeepSeek Harness（dsh）** 的分级推送通知系统，也支持作为 **Magpie 网关 hook 插件**直接安装。支持 **11 个通知渠道**，各入口复用通知配置与发送脚本。

最新兼容性基准、事件差异和市场收录规则见 [兼容性说明](docs/compatibility.md)（2026-11-14）。

## 为什么需要分级通知？

Agent 任务常常需要几秒到几十分钟不等。你不会一直盯着终端，但又需要在合适的时候回来操作。

**cc-notify-hooks 将通知分为两级**：

**短通知（秒级）** — 你可能只是切到了浏览器或聊天窗口。系统通知、手机推送这类**即时触达**的渠道会在几秒内提醒你"Claude 需要你"。如果你看到通知并回来操作了，后续推送自动取消——不会再打扰你。

**长通知（分钟级）** — 你可能离开了电脑、在开会、甚至不在手机旁。企业微信群、飞书群、Slack 频道这类**团队/异步渠道**会在几分钟后兜底通知。即使你错过了短通知，最终也能从工作沟通工具里看到任务状态。

**核心机制**：每次推送前检查待发标记（pending 文件）是否还在。宿主报告后续输入、提问结束等活动后，清除对应会话或请求的标记，其他会话继续保留。具体取消时机取决于宿主提供的事件，见下方事件覆盖表。

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
Claude Code / Codex CLI / dsh 事件，或 Magpie 网关回调
    │
    ├─ Codex request_user_input → PreToolUse dispatcher → 等待输入通知
    │                                      └─ PostToolUse → 定向取消
    ▼
notify.sh ── 清除当前 Session 的旧 pending → 创建新 pending
    │
    │  ┌── 短通知 ──────────────────────────────────┐
    ├─ │ 3s  → pending 还在？ → macOS 系统通知      │
    ├─ │ 5s  → pending 还在？ → Telegram             │
    ├─ │ 15s → pending 还在？ → Bark / ntfy / ...    │
    │  └────────────────────────────────────────────┘
    │  ┌── 长通知 ──────────────────────────────────┐
    └─ │ 5m  → pending 还在？ → 企微 / 飞书 / Slack │
       └────────────────────────────────────────────┘

宿主报告新输入、提问结束、工具完成或支持的中断事件
    └─→ clear_pending.sh → 清除对应 pending → 取消尚未发送的推送
         （短通知解决了，长通知就不发了）
```

## 安装

### 依赖

- **jq** — 解析 JSON（`brew install jq` / `apt install jq`）
- **curl** — 发送推送（通常已预装）

### 方式一：Claude Code Marketplace（推荐 Claude 用户）

Claude Code 2.1.275 及以上可用一条命令注册来源并安装：

```text
/plugin install cc-notify-hooks --marketplace MarioZZJ/cc-notify-hooks
```

也可分别注册和安装：

```
/plugin marketplace add MarioZZJ/cc-notify-hooks
/plugin install cc-notify-hooks@cc-notify-hooks
```

安装后运行 `/reload-plugins` 刷新，然后执行 `/cc-notify-hooks:config` 启动交互式配置向导（见下方[配置](#配置)章节）。

### 方式二：Codex CLI Marketplace（推荐 Codex 用户）

仓库根目录的 `.agents/plugins/marketplace.json` 是 Codex marketplace，实际插件目录是 `plugins/cc-notify-hooks/`。在终端执行：

```bash
codex plugin marketplace add MarioZZJ/cc-notify-hooks
codex plugin add cc-notify-hooks@cc-notify-hooks
```

Codex 0.169.0 的 hooks 已默认开启，无需额外配置。如果此前关闭过，在 `${CODEX_HOME:-~/.codex}/config.toml` 恢复：

```toml
[features]
hooks = true
```

`codex_hooks` 是旧版兼容别名。安装后启动新会话，打开 `/hooks` 审阅并信任 hooks；桌面端也可用 **Settings > Hooks**。升级后即使命令定义不变，只要插件脚本改变，也需要重新审阅。

更新仓库来源并同步插件：

```bash
codex plugin marketplace upgrade cc-notify-hooks
```

如需固定版本，添加来源时使用 `--ref <已发布的 tag>`；固定 tag 的 marketplace 更新仍跟随该 tag。

注意：Codex 的 hook 命令运行目录是当前会话 `cwd`，不是插件根目录。`.codex-plugin/plugin.json` 只负责把 `hooks/codex-hooks.json` 作为生命周期配置打包进去；hook 命令不能写成 `./scripts/...`。本插件使用 Codex 提供的 `PLUGIN_ROOT` 定位脚本、使用 `PLUGIN_DATA` 保存插件配置和状态，因此兼容自定义 `CODEX_HOME`，不依赖固定的插件缓存路径。

### 方式三：dsh 原生插件

dsh 包名为 **`dsh-notify-hooks`**，使用已有的 `dsh-plugin` 原生 Cordis 模块。包清单位于 `plugins/cc-notify-hooks/package.json`，包含通知脚本与配置模板。本次升级调整审批取消和回合结束的判定，并支持 profile 插件管理器注册。

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh dsh web          # CLI 的 web profile
# 桌面版附带的 dsh 命令：
bash install.sh dsh desktop      # 已初始化的 desktop profile
```

新安装调用 `dsh plugin --profile <profile> add <仓库绝对路径>/plugins/cc-notify-hooks`，注册的包名为 `dsh-notify-hooks`。如检测到 v2.4.0 安装器写入的 home 级 `cc-notify-hooks` 条目，则保留旧链接作为兼容别名，加载更新后的模块，避免重复注册。使用 dsh 0.2.2-rc.3 或更新的兼容版本；普通 npm CLI 不能管理 `desktop` profile。未开启 HMR 时需重启对应宿主。

也可从自定义索引安装：在 dsh 的 `Experimental plugins` 中启用 `Custom plugin indexes`，进入 `Discover` 并添加以下索引地址，选择 `dsh-notify-hooks`：

```text
https://mariozzj.github.io/cc-notify-hooks/dsh-index.json
```

索引指向 v2.5.0 的发布提交，包目录为 `plugins/cc-notify-hooks`。

### 方式四：Magpie 直接插件

Magpie 包名为 **`agent-notify-hooks`**，由仓库根目录的 `package.json` 声明。

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh magpie
```

安装器调用 `magpie plugin add <仓库绝对路径>`，并设置 `gatewayTimeoutMs: 3000`。插件通过异步 `onRequest` / `onResponse` 观察经过 Magpie 的请求，建议使用 Magpie 0.1.4174 或更新的兼容版本。

通过 Magpie 目录或 `magpie plugin add` 直接安装时，包本身也提供 `gatewayTimeoutMs: 3000`。如果尚无通知配置，请把 [配置模板](https://raw.githubusercontent.com/MarioZZJ/cc-notify-hooks/v2.5.0/plugins/cc-notify-hooks/config/notify.example.json) 保存为 `~/.config/cc-notify-hooks/notify.json`，再启用需要的渠道并填写凭据；已有配置可通过下方 `configPath` 选项继续使用。

Magpie 显示“模型响应完成”或“模型请求异常”。一次模型响应可能只是 Agent 多轮任务的一部分；审批按钮、用户回答和客户端中断由原生 Agent 集成处理。缺少会话 id 或明确标记为子代理的网关请求会跳过。原生 hooks 和 Magpie 同时启用会分别通知，可按所需事件选择入口。

本包复用 Claude Code、Codex 和 dsh 的通知配置，提供按渠道独立延迟的队列，以及同会话后续请求的取消处理，覆盖 macOS、Slack、Discord、Pushover 等 11 个渠道。通知默认包含响应摘要。Magpie 社区已有的 [Notify](https://github.com/magpie-community/plugins/tree/main/packages/notify) 则提供任务时长筛选、账号掉线提醒和内嵌配置页面；选择时可依据这些实际差异。`agent-notify-hooks` 需要 Bash、`jq` 和 `curl`，渠道通过本地 JSON 配置。

### dsh / Magpie 通知配置

dsh 沿用 `${DSH_HOME:-~/.dsh}/cc-notify-hooks/notify.json`，新安装的状态目录为同目录下的 `state`；已有配置中的 `stateDir` 继续生效。Magpie 使用 `~/.config/cc-notify-hooks/notify.json` 和其下的 `state/magpie`。安装器只在配置不存在时创建文件，默认启用 macOS 通知。本地安装引用本仓库，安装后保留目录。Magpie 也可直接执行 `magpie plugin add github:MarioZZJ/cc-notify-hooks` 安装远程包。

dsh 可在 profile 的 `cordis.patch.yml` 为插件配置自定义路径：

```yaml
- id: dsh-notify-hooks
  config:
    configFile: /absolute/path/notify.json
    stateDir: /absolute/path/state/dsh
```

旧版 home 级安装继续编辑其 `id: cc-notify-hooks` 条目，配置字段相同。

Magpie 可为已安装的插件设置选项；本地安装时用安装命令中的仓库绝对路径作为 `<插件名或来源>`：

```bash
magpie plugin options "<插件名或来源>" '{"configPath":"/absolute/path/notify.json","stateDir":"/absolute/path/state/magpie","gatewayTimeoutMs":3000}'
```

### 方式五：本地 Claude 插件模式

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git

# Claude Code
claude --plugin-dir ./cc-notify-hooks/plugins/cc-notify-hooks

# Codex CLI: 见上文 Codex Marketplace 方式
```

### 方式六：Claude / Codex 独立安装

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh                  # 交互式选择安装目标
bash install.sh claude           # 直接装到 Claude Code
bash install.sh codex            # 直接装到 Codex CLI
```

Claude / Codex 分支会交互式引导你选择渠道、输入凭证，自动生成配置：

- **Claude 分支**：写 `~/.claude/hooks/notify.json`，合并 hooks 到 `~/.claude/settings.json`
- **Codex 分支**：写 `${CODEX_HOME:-~/.codex}/cc-notify-hooks/notify.json`，合并 hooks 到 `${CODEX_HOME:-~/.codex}/hooks.json`，安装后在 `/hooks` 中信任

独立安装会保留其他插件的 hooks。安装后启动新会话；Codex 还需在 `/hooks` 中审阅。Claude 的 `/reload-plugins` 用于刷新插件模式。

### 验证

```bash
bash test_notify.sh              # 测试所有已启用渠道
bash test_notify.sh bark         # 测试单个渠道
bash test_notify.sh list         # 查看已启用渠道及延迟
bash test_notify.sh hook         # 模拟 Claude Code hook 流程
bash test_notify.sh codex        # 模拟 Codex CLI PermissionRequest 事件
bash test_notify.sh codex-plugin-hooks  # 验证 Codex 插件 hook 路径解析
bash test_notify.sh user-input   # 验证 request_user_input dispatcher 与模板
bash test_notify.sh state        # 验证多 Session 状态隔离与精确去重
bash test_notify.sh render       # 验证通知内容模板
```

## 事件覆盖与取消

| 入口 | 通知事件 | 清理时机 |
|---|---|---|
| Claude | `Notification`、`AskUserQuestion`、`Stop`、`StopFailure` | 新输入、普通工具开始、工具成功/失败、提问结束、`SessionEnd` |
| Codex | `PermissionRequest`、`request_user_input`、`Stop` | 新输入、普通工具开始、工具完成、提问结束、`Interrupt`、`SessionEnd` |
| dsh | 审批等待、结构化提问、正常回合结束、错误/阻止/输出上限 | 审批决定、提问结束或取消、新输入、新回合、Agent 销毁、插件卸载 |
| Magpie | 可识别的完整文本响应、请求错误 | 同会话下一次网关请求 |

Claude 的 `permission_prompt` 通常先由宿主等待约 6 秒，`idle_prompt` 通常约 60 秒，再进入本插件的渠道延迟。Claude / Codex 的 `PreToolUse` 在权限确认之前；工具结束清理不能保证在点击审批按钮时立即发生。Codex 的自动审阅也会触发 `PermissionRequest`，当前 payload 尚不能精确区分人工等待，详见 [#3](https://github.com/MarioZZJ/cc-notify-hooks/issues/3)。

## 配置

### 方式一：交互式配置（推荐）

在 Claude Code 中运行：

```
/cc-notify-hooks:config
```

Codex 插件也提供 `config` 配置技能及安装后的 setup 入口。dsh 和 Magpie 默认直接编辑上方公共配置文件。

配置向导会引导你：
1. 选择要启用的**短通知渠道**（macOS、Telegram、Bark 等）
2. 选择要启用的**长通知渠道**（企业微信、飞书、Slack 等）
3. 逐个输入渠道凭证，附带获取指引
4. 调整延迟时间
5. 测试渠道连通性

已有配置的渠道会标注当前状态，支持随时修改。

### 方式二：手动编辑配置文件

运行时依次查找：`CC_NOTIFY_CONFIG`、`PLUGIN_DATA/notify.json`、`CLAUDE_PLUGIN_DATA/notify.json`、`~/.config/cc-notify-hooks/notify.json`、`${CODEX_HOME:-~/.codex}/cc-notify-hooks/notify.json`、`${REASONIX_HOME:-~/.reasonix}/cc-notify-hooks/notify.json`、`${DSH_HOME:-~/.dsh}/cc-notify-hooks/notify.json`、`~/.claude/hooks/notify.json`。显式配置与宿主插件数据优先；独立安装器会在命令中绑定自己生成的配置文件。

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
| `events` | 可选，响应的事件类型，默认 `["notification", "stop"]`。等待输入、权限、异常以及 Magpie 网关响应均使用 `notification` 渠道规则；原生 Agent 的正常回合结束使用 `stop` |
| `format` | 可选，长通知渠道的展示格式。飞书默认 `card`，企业微信/钉钉/Slack 默认 `markdown`，Discord 默认 `embed` |
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
| PreToolUse | `request_user_input` 调用前 | 发送“需要回复”通知；其他工具清除当前 Session pending |
| PostToolUse | `request_user_input` 收到回答后 | 只取消当前 Session 尚未发送的输入通知 |

> Codex 没有独立的等待输入事件。插件通过 `PreToolUse(request_user_input)` 精确识别等待状态，并复用 `notification` 渠道配置。

## 通知内容

通知先归一为统一字段，再按短通知和长通知分别渲染。标题使用实际 Agent 名，不再写死为 Claude。

| 场景 | 标题 |
|------|------|
| Claude Code Notification idle_prompt | `Claude Code · 等待响应 ⏳` |
| Codex PermissionRequest | `Codex · 需要确认 🔔` |
| Codex request_user_input | `Codex · 需要回复 🔔` |
| Stop | `{Agent} · 任务完成 ✅` |
| 异常 / 未知事件 | `{Agent} · 异常 ⚠️` |

短通知正文只保留打断所需信息：

```text
[项目名] summary_short · tool_name
```

其中 `tool_name` 是条件字段，没有就不显示；`permission_mode` 不进入通知正文。

Codex 等待输入使用专用短正文，包含问题数和短 Session id：

```text
[项目名] 首个问题摘要 · 2 个问题 · Session 019eabcd
```

长通知正文第一行显示 `summary_short`，随后显示定位字段：

```text
summary_short

项目: project
事件: hook_event_name
工具: tool_name      # 有值才显示
Session: session_short

model · cwd · hostname
```

等待输入的长通知额外显示问题数、首题选项和完整 Session id。飞书默认发送消息卡片；企业微信、钉钉、Slack 使用近似 Markdown 模板；Discord 使用 embed。`summary_short` 来自 `message/prompt`、首个结构化问题或 `last_assistant_message` 的首个非空行，最长保留 120 字。

## 过滤规则

| 规则 | 说明 |
|------|------|
| 子智能体过滤 | Claude/Codex 的 `agent_id` 非空时跳过；dsh 使用 `session.header.origin`；Magpie 使用 `ctx.kind` |
| Stop 循环保护 | `stop_hook_active=true` 时跳过 |
| `/exit` 静默 | 只抑制当前 Session 后续的 Stop 事件 |
| Rate Limiting | 按 Session + 事件类别限流；结构化问题和 dsh 审批使用调用 id 去重 |

## 文件结构

```
cc-notify-hooks/
├── package.json            # Magpie 包 agent-notify-hooks
├── adapters/
│   └── magpie/hooks.mjs     # onRequest / onResponse
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
│   ├── package.json         # dsh-notify-hooks 包清单
│   ├── dsh-plugin/          # 原生事件模块与 cordis.patch.yml
│   ├── reasonix-plugin.json
│   ├── README.md           # 安装包及目录提交说明
│   ├── skills/config/SKILL.md
│   ├── hooks/
│   │   ├── hooks.json
│   │   └── codex-hooks.json
│   ├── scripts/
│   │   ├── notify.sh
│   │   ├── pre_tool_use.sh
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
│   ├── codex.sh             # Codex CLI 安装分支
│   ├── dsh.sh               # dsh 安装入口
│   ├── reasonix.sh
│   └── native.sh            # dsh / Magpie 原生插件安装
└── test_notify.sh -> plugins/cc-notify-hooks/test_notify.sh
```

调试日志：`/tmp/claude-hooks-debug.log`

## 卸载

**Claude Code 插件**：在 Claude Code 中 `/plugin` 管理。

**Codex CLI 插件**：在 Codex 中 `/plugins` 管理，或执行 `codex plugin remove cc-notify-hooks@cc-notify-hooks`。

**dsh profile 插件**：`dsh plugin --profile <profile> remove dsh-notify-hooks`。旧版 home 级安装则删除 `${DSH_HOME:-~/.dsh}/cordis.patch.yml` 中的 `cc-notify-hooks` 条目，并移除 `~/node_modules/@dsh-local/dsh-cc-notify` 兼容链接。

**Magpie**：`magpie plugin rm "<插件名或来源>"`。

**独立安装（Claude）**：
```bash
rm -rf ~/.claude/hooks/scripts ~/.claude/hooks/notify.json ~/.claude/hooks/state
# 手动编辑 ~/.claude/settings.json 移除相关 hooks
```

**独立安装（Codex）**：
```bash
rm -rf ~/.codex/cc-notify-hooks
# 手动编辑 ~/.codex/hooks.json，只移除本插件的处理器
```

## 插件市场

- **Claude**：本仓库提供自建 marketplace。官方目录通过开发者门户提交，目录图标和申请材料由 [#5](https://github.com/MarioZZJ/cc-notify-hooks/issues/5) 跟踪。
- **Codex**：本仓库提供自建 marketplace。OpenAI 公共目录目前不接收包含生命周期 hooks 的插件。
- **dsh**：已提供 [自定义索引](https://mariozzj.github.io/cc-notify-hooks/dsh-index.json)，包名为 `dsh-notify-hooks`，Git 来源指向 v2.5.0 发布提交的 `plugins/cc-notify-hooks` 目录。
- **Magpie**：仓库已添加 `magpie-plugin` topic。根包 `agent-notify-hooks` 使用 `magpie.hooks` 入口，可从本仓库安装；社区发现与列表收录状态由 #5 跟踪。

来源、版本和当前限制见 [兼容性说明](docs/compatibility.md#市场分发)。

Claude 开发者门户的填写内容、数据处理说明和账号声明见 [目录提交材料](docs/marketplace-submission.md)。

## License

MIT
