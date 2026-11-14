# cc-notify-hooks — Claude 目录提交材料

资料日期：2026-11-15（Asia/Shanghai）。适用于 Claude 开发者门户的插件包（Plugin bundle）提交；数据处理说明对应当前仓库的 Claude Code hooks 与共享通知脚本。

## 1. 来源与展示字段

| 门户字段 / 材料 | 填写内容 |
|---|---|
| 提交类型 | Plugin bundle |
| Name | `cc-notify-hooks` |
| Repository | `MarioZZJ/cc-notify-hooks` |
| Plugin path | `plugins/cc-notify-hooks` |
| Branch or tag / Tracked branch or tag | `main` |
| 当前清单版本 | `2.5.0`，以提交所对应提交中的清单为准 |
| 清单作者 | `MarioZZJ` |
| License | MIT |
| 分类建议（如门户提供） | Productivity / 开发效率 |
| 项目主页 | [MarioZZJ/cc-notify-hooks](https://github.com/MarioZZJ/cc-notify-hooks) |
| 问题反馈 | [仓库 Issues](https://github.com/MarioZZJ/cc-notify-hooks/issues) |
| 插件内图标 | [plugins/cc-notify-hooks/assets/icon.png](../plugins/cc-notify-hooks/assets/icon.png) |
| 文档站图标副本 | [docs/assets/icon.png](assets/icon.png) |
| 图标规格 | 1254 × 1254 PNG，1,143,318 字节 |

名称、短描述和详细展示内容由门户读取插件清单与插件目录内的 README；以下文案可用于对应输入栏或后续维护这两个源文件。仅编辑本材料不会更改目录展示。[官方提交说明][submit]

**中文短描述**

为 Claude Code 的等待输入、权限请求、任务完成和异常提供分级通知；按渠道延迟推送，后续交互取消待发提醒。

**English short description**

Tiered alerts for Claude Code questions, permissions, completion, and failures. Follow-up activity cancels queued alerts.

**中文用途与展示正文**

cc-notify-hooks 在 Claude Code 需要回复、请求权限、结束任务或报告受支持的失败事件时发送提醒。用户可分别设置桌面、手机和团队消息渠道的延迟；宿主报告后续输入或相关工具活动后，插件取消对应会话尚未发送的提醒。

插件通过本地 Bash 脚本运行，支持 macOS 系统通知、Bark、Telegram、Pushover、ntfy、Gotify、企业微信、飞书、钉钉、Slack 和 Discord。网络通知使用用户提供的账号凭据、服务器地址或 webhook。通知可包含项目、消息摘要和会话信息；丰富格式还可包含工作目录、主机名、模型和首题选项。默认调试日志会在本机保存通知脚本收到的完整事件载荷，插件没有固定的日志保留期限。

**English purpose and listing description**

cc-notify-hooks alerts you when Claude Code needs an answer, requests permission, finishes a turn, or reports a supported failure event. Set separate delays for desktop, phone, and team messaging channels. When the host reports follow-up input or relevant tool activity, the plugin cancels unsent notifications for the corresponding session.

The plugin runs local Bash scripts and supports macOS notifications, Bark, Telegram, Pushover, ntfy, Gotify, WeCom, Feishu, DingTalk, Slack, and Discord. Network channels use credentials, server addresses, or webhooks supplied by the user. Notifications can include project names, message summaries, and session identifiers; rich formats can also include working directories, hostnames, models, and first-question options. A local debug log records full incoming notification-hook payloads by default, without a plugin-defined retention period.

依据：[插件 README][plugin-readme]、[仓库 README][repo-readme]、[Claude 清单][manifest]、[事件定义][hooks]、[通知调度器][notify]。

## 2. 平台、依赖与安装配置

**平台和依赖**

- 申报使用场景：Claude Code 本地命令 hooks。脚本依赖 Bash、`jq`、`curl` 以及常见 Unix 命令。
- macOS 系统通知还需要 `osascript`。Linux 等具备上述命令的环境可使用已配置的网络渠道；本次申报的目标为 Claude Code。
- 仓库 README 的一条命令安装方式要求 Claude Code 2.1.275 或以上。
- 通知渠道需要用户在相应服务中准备设备 key、机器人 token、用户标识、topic、自建服务器或 webhook。macOS 通知无需渠道凭据。
- 仓库还提供其他宿主的安装入口；本次提交的插件目录是上表指定目录。

**中文安装与配置说明**

在 Claude Code 中执行：

```text
/plugin install cc-notify-hooks --marketplace MarioZZJ/cc-notify-hooks
/reload-plugins
/cc-notify-hooks:config
```

也可分别添加来源和安装：

```text
/plugin marketplace add MarioZZJ/cc-notify-hooks
/plugin install cc-notify-hooks@cc-notify-hooks
```

配置向导允许选择渠道、填入凭据、调整延迟和事件范围。手动配置可参考插件内的 [config/notify.example.json][example]，把所需渠道的 `enabled` 设为 `true` 并填入自己的值。将配置保存在用户配置目录或宿主插件数据目录，避免放入插件安装缓存。`CC_NOTIFY_CONFIG` 可指定配置文件。

示例配置仅启用 macOS 的 `notification` 类事件，网络渠道均默认禁用。没有找到任何配置文件时，macOS 对 `notification` 类事件安排 3 秒延迟的系统通知；其他平台直接退出。正常任务结束使用 `stop`，需要在渠道事件设置中允许。配置存在但没有可用渠道时不会发送通知。

**English installation and configuration**

Install Bash, `jq`, and `curl`. macOS desktop notifications also require `osascript`. In Claude Code 2.1.275 or later, run `/plugin install cc-notify-hooks --marketplace MarioZZJ/cc-notify-hooks`, then `/reload-plugins` and `/cc-notify-hooks:config`.

Choose channels, enter your own credentials or webhook URLs, and set delays and event filters. For manual setup, use `config/notify.example.json` from the installed plugin and store the configuration in your user configuration or plugin data directory. `CC_NOTIFY_CONFIG` can select an explicit file. The example enables only macOS attention notifications; network channels are disabled. Enable `stop` events if you want normal turn-completion alerts.

With no configuration file, macOS schedules attention notifications after three seconds and other platforms send nothing. Cancellation depends on the host delivering the relevant activity event and affects only messages that have not yet been sent.

**配置文件查找顺序**

运行时选择下列顺序中第一个存在的文件。显式路径不存在时会继续查找后续位置。

1. `${CC_NOTIFY_CONFIG}`
2. `${PLUGIN_DATA}/notify.json`
3. `${CLAUDE_PLUGIN_DATA}/notify.json`
4. `${HOME}/.config/cc-notify-hooks/notify.json`
5. `${CODEX_HOME:-${HOME}/.codex}/cc-notify-hooks/notify.json`
6. `${REASONIX_HOME:-${HOME}/.reasonix}/cc-notify-hooks/notify.json`
7. `${DSH_HOME:-${HOME}/.dsh}/cc-notify-hooks/notify.json`
8. `${HOME}/.claude/hooks/notify.json`

因此，已有的共享配置或其他宿主配置也可能被选中；“默认不启用网络渠道”仅描述示例及无配置情形。

依据：[仓库 README][repo-readme]、[配置向导][config-skill]、[示例配置][example]、[通知调度器的配置加载与发送队列][notify]。

## 3. 数据处理：可直接填写的英文答案

下面的回答与后面的数据明细配套使用；具体选项名称以门户当前表单为准。

### Reads or stores personal data

**Answer: Yes.**

The plugin processes event JSON supplied by Claude Code. Depending on the event, it can contain user prompts, notification or error messages, assistant output, tool names and arguments, structured questions and options, session identifiers, working directories, and transcript-path metadata. It also reads a user-selected local notification configuration containing channel credentials and destinations, and obtains the local hostname.

During normal operation, the notification dispatcher appends the full received event payload to `/tmp/claude-hooks-debug.log` before event filtering. The payload may contain personal information or secrets included in prompts or tool arguments. Local state files retain session-related identifiers, event kinds, timestamps, and tool-call identifiers for cancellation and deduplication. The plugin does not provide automatic redaction of these payloads.

### Sends data to services other than declared connectors

**Answer: Yes, when a network channel is enabled.**

The plugin sends HTTP requests directly from the user's machine using `curl`; these notification services are not declared MCP connectors. Destinations include `api.day.app` or a user-configured Bark server, `api.telegram.org`, `api.pushover.net`, `ntfy.sh` or a user-configured ntfy server, a user-configured Gotify server, and user-provided WeCom, Feishu, DingTalk, Slack, or Discord webhook URLs.

Messages contain a title and a project/message summary. Rich formats can additionally send the event and tool name, model, working directory, hostname, question count, first-question option labels, and session identifier. Structured-question rich notifications can contain the full session identifier; other rich notifications normally use its first eight characters. Required channel credentials or routing identifiers are sent to the selected provider as part of its request.

Users control custom server and webhook destinations. The code does not enforce a domain allowlist or require HTTPS for user-supplied URLs. macOS notifications are displayed through the local operating system. The bundled optional cmux channel passes the title and body to the local `cmux` command when configured and available.

### Data retention and deletion

**Answer: No fixed plugin-enforced retention period.**

Channel settings and credentials are stored in a local plaintext JSON configuration until changed or removed by the user. The plugin does not encrypt this configuration. The configuration skill instructs the host to create new configuration files with owner-only read/write permissions, but the runtime does not enforce or repair file permissions.

The default debug log, `/tmp/claude-hooks-debug.log`, is append-only from the plugin's perspective. There is no built-in rotation, maximum size, expiry, or scheduled deletion. Pending markers are normally removed after the sender finishes, when a newer event replaces them, or when a matching cancellation hook runs. Markers can remain when the queue is empty or execution is interrupted. Rate-limit records have no expiry cleanup. Exit-suppression markers are removed on specific subsequent events, rather than on a timer.

Cancellation removes unsent queue markers; it does not erase debug logs or credentials and does not recall notifications already delivered. Retention by notification providers, recipient devices, the operating system, or the host application's conversation history is outside this plugin's deletion logic. Disabling a channel or uninstalling the plugin does not establish that these records have been deleted.

### Intended for people under 18

**Maintainer input required.** 由维护者根据实际目标受众填写；本材料不预选 Yes 或 No。

依据：[通知调度器][notify]、[清理脚本][clear]、[提问分发脚本][pre-tool]、[格式化函数][format]、[各渠道源码][channels]、[配置向导][config-skill]。门户提问类别来源：[官方提交说明][submit]。

## 4. 数据读取与通知字段明细

| 数据来源 | 读取和用途 | 保存或发送范围 |
|---|---|---|
| hook 标准输入 | `notify.sh`、`pre_tool_use.sh`、`clear_pending.sh` 接收宿主提供的 JSON；提问分发脚本仅将含问题的受支持工具事件转交通知脚本 | 通知脚本记录自己收到的完整载荷；清理脚本本身不写该调试日志 |
| 消息与输出 | `message`、`prompt`、`error_description`、`error`、`last_assistant_message` / `lastAssistantText` | 摘要取相应文本的首个非空行并截至最多 120 字符；完整原始字段可留在调试日志 |
| 结构化问题 | `tool_input.questions` 的数量、首题 `header` / `question`、首题选项 `label` | 摘要优先首题标题，其次题目正文；丰富格式发送问题数和首题选项。选项标签没有该 120 字符摘要限制 |
| 会话与调用 | `session_id` / `sessionId`、`turn_id`、`tool_use_id` | 用于状态隔离、去重；短通知可带 8 字符会话摘要，结构化提问的丰富格式可带完整会话 id |
| 项目与环境 | `cwd`、`model`，并调用 `hostname -s` 或 `hostname` | 项目名来自工作目录末级名称；丰富格式可外发完整工作目录、模型和主机名 |
| 控制元数据 | `hook_event_name` / `event`、`notification_type`、`agent_id`、`stop_hook_active`、`permission_mode`、`transcript_path`、工具名称 | 用于事件、宿主识别及过滤；`permission_mode` 不进入通知正文，但可存在原始日志中 |
| 用户配置 | 选中的 `notify.json`，以及路径、宿主标识和状态目录相关环境变量 | 读取渠道开关、延迟、事件过滤、显示格式、目标和凭据；凭据用于渠道请求 |

`transcript_path` 用于识别宿主，通知脚本没有打开该路径读取会话文件。通知脚本也没有按 `cwd` 扫描项目源码；宿主已经放入事件载荷的代码、文本或工具参数仍可能写入日志。日志写入发生在子代理过滤、Stop 循环过滤及限流之前，跳过发送不等于未保存收到的载荷。

依据：[通知调度器][notify]、[提问分发脚本][pre-tool]、[清理脚本][clear]、[格式化函数][format]。

## 5. 逐渠道目的地与凭据

“短内容”指标题和正文摘要，正文包含项目名，并按事件带工具名或问题数与短会话 id。“丰富内容”在摘要之外加入事件、工具、模型、工作目录、主机名、会话及适用的问题字段。五种团队消息渠道可用 `format: "text"` 改为短内容。

| 渠道 / 代码 | 实际请求目标 | 发送内容及凭据 / 路由标识 |
|---|---|---|
| macOS / `macos.sh` | 本机 `osascript` | 短内容与提示音；该脚本不发 HTTP 请求 |
| Bark / `bark.sh` | `${server}/push`；默认 `https://api.day.app/push` | JSON 中包含短内容、`device_key`、分组、提醒级别及可选提示音；`server` 可自定义 |
| Telegram / `telegram.sh` | `https://api.telegram.org/bot${bot_token}/sendMessage` | JSON 中包含 `chat_id` 和短内容；机器人 token 位于 URL 路径 |
| Pushover / `pushover.sh` | `https://api.pushover.net/1/messages.json` | 请求体包含 `app_token`（`token`）、`user_key`（`user`）、标题及短正文 |
| ntfy / `ntfy.sh` | `${server}/${topic}`；默认服务器 `https://ntfy.sh` | 短正文、标题与优先级请求头；topic 位于 URL 路径。当前脚本不设置 token / Authorization 请求头 |
| Gotify / `gotify.sh` | 用户填写的 `${server}/message?token=${app_token}` | JSON 中包含短内容与优先级；应用 token 位于 URL 查询参数 |
| 企业微信 / `wechat.sh` | 用户填写的完整 `webhook`；模板示例主机为 `qyapi.weixin.qq.com` | 默认 Markdown 丰富内容；Webhook URL 通常包含访问 key |
| 飞书 / `feishu.sh` | 用户填写的完整 `webhook`；模板示例主机为 `open.feishu.cn` | 默认卡片丰富内容；Webhook URL 包含机器人标识 / 访问凭据 |
| 钉钉 / `dingtalk.sh` | 用户填写的完整 `webhook`；模板示例主机为 `oapi.dingtalk.com` | 默认 Markdown 丰富内容；Webhook URL 包含访问 token |
| Slack / `slack.sh` | 用户填写的完整 `webhook`；模板示例主机为 `hooks.slack.com` | 默认 `text` 加 `blocks` 丰富内容；Webhook URL 本身是敏感凭据 |
| Discord / `discord.sh` | 用户填写的完整 `webhook`；模板示例主机为 `discord.com` | 默认 embed 丰富内容；Webhook URL 含 id 和 token |
| 附带 cmux / `cmux.sh` | 本机 `cmux notify`，失败或不存在时尝试 OSC 777 输出 | 短内容；不在示例配置和 11 渠道展示清单内。主调度器重定向后台标准输出，不能承诺其 OSC 回退能在该路径下显示 |

配置中的 `server` 和 `webhook` 直接参与构造请求。以上示例域名不构成允许名单，实际目标可以是用户自己的服务；代码没有限制自定义目标必须使用 HTTPS。运行时只调用配置中启用且存在对应脚本的渠道。上述通知路径中未发现写死的项目维护者接收端或独立分析上报端。

依据：[渠道目录][channels]中的各同名脚本、[示例配置][example]、[发送队列][notify]、[格式化函数][format]。

## 6. 本地保存、保留与清理

| 保存项 | 位置与内容 | 保留及删除行为 |
|---|---|---|
| 通知配置与凭据 | 第 2 节查找顺序选中的 `notify.json`；明文 JSON 保存 key、token、chat id、topic、server、webhook 等 | 持续保存到用户修改或删除；配置技能关闭渠道时保留其凭据。运行时不加密、不自动删除或收紧权限 |
| 调试日志 | 固定 `/tmp/claude-hooks-debug.log`；包含时间、事件类别及通知脚本收到的完整原始载荷 | 正常运行自动追加；没有轮转、大小上限、保留天数、定时清除或脱敏。不能把 `/tmp` 位置视为插件承诺自动删除 |
| 待发标记 | 状态目录下 `pending_<session>_<kind>_<call>_<time>_<pid>`；文件内容为事件类别 | 新通知通常替换同会话标记；宿主清理事件删除对应标记；后台队列结束删除本次标记。空队列退出或进程中断可留下文件，没有超时回收 |
| 限流记录 | 状态目录下 `last_<session>_<kind>`；内容为时间戳和调用 id | 后续同会话同类事件覆盖；`clear_pending.sh` 不删除，没有过期清扫 |
| 退出抑制标记 | 状态目录下 `exiting_<session>` | `/exit` 输入创建；相应 Stop 处理或后续非 `/exit` 输入移除。仅发生 `SessionEnd` 不保证移除，没有定时删除 |
| 系统显示与外部服务 | macOS 通知系统、用户选定的推送服务、群聊和设备 | 插件未实现删除已交付消息的接口，不能代表这些系统承诺保留期限 |

状态目录选择：

```text
CC_NOTIFY_STATE_DIR
  若未指定：${PLUGIN_DATA}/state
  若 PLUGIN_DATA 未指定：${CLAUDE_PLUGIN_DATA}/state
  若两个插件数据目录均未指定：${HOME}/.claude/hooks/state
```

状态文件名中的会话和调用标识经过字符替换并截到 96 字符，属于可关联标识，不是匿名化或加密。通知与清理脚本使用同一目录规则。

配置技能要求新建文件仅当前用户可读写，但这属于向宿主给出的写入指令；通知脚本本身不执行权限修复。仓库的独立 Claude 安装器也没有为生成的配置强制设置 `0600`。日志及状态文件创建权限依赖执行环境的 `umask` 和已有权限，不能统一声明仅用户本人可读。

配置向导通过宿主的问答工具收集凭据；在对话中输入的值还可能进入宿主会话记录。插件没有清除宿主会话记录的机制。`CC_NOTIFY_RENDER_ONLY=1` 会跳过日志和状态写入并只输出渲染结果，但正常 hooks 没有启用该模式，不能用它描述默认保存行为。

**Claude Code 的 pending 清理时机**

- `UserPromptSubmit` 清理当前会话的待发标记，同时处理 `/exit` 标记。
- `PreToolUse` 遇到有问题的 `AskUserQuestion` 时创建提问通知；普通工具开始时清理当前会话待发标记。
- `PostToolUse` / `PostToolUseFailure` 清理 `notification` 类标记；`AskUserQuestion` 还清理 `user_input` 类标记。
- `SessionEnd` 清理当前会话待发标记。这里的清理不包括调试日志、配置、限流记录或所有退出标记。
- 发送器在每个渠道发送前检查标记。删除标记后，仍在等待的后台进程会在下次检查时停止后续发送；已经开始的网络请求或已交付消息不会被撤回。

独立安装另有本地备份行为：`install/claude.sh` 会在覆盖已有 `settings.json` 前创建带时间戳的备份，并在旧 `notify.conf` 迁移时保留 `.bak`；安装器没有给这些备份设置自动删除期限。这属于选择独立安装入口时的行为。

依据：[通知调度器][notify]、[清理脚本][clear]、[Claude 事件定义][hooks]、[配置向导][config-skill]、[独立安装器][installer]。

## 7. 需要维护者本人填写或确认

以下项目保持未签署状态；代码事实不能替代维护者对受众、账户和声明的确认。

| 门户项目 | 待填写内容 / 状态 |
|---|---|
| Intended for people under 18 | **待维护者填写 Yes / No**，依据实际目标受众 |
| 提交组织与资格 | **待维护者确认**：实际 Claude 组织、允许提交的方案和角色，以及代表该组织提交的资格 |
| GitHub 身份与权限 | **待维护者确认**：当前 Claude 组织连接的 GitHub 账号具有目标仓库的推送权限 |
| Contact email | `i@mariozzj.cn`，来自仓库 `.claude-plugin/marketplace.json` 的 `owner.email` |
| Compliance acknowledgement 1 | **待门户原文 → 维护者逐项阅读并确认** |
| Compliance acknowledgement 2 | **待门户原文 → 维护者逐项阅读并确认** |
| Compliance acknowledgement 3 | **待门户原文 → 维护者逐项阅读并确认** |
| Compliance acknowledgement 4 | **待门户原文 → 维护者逐项阅读并确认** |
| 隐私政策 URL（如表单要求） | **待维护者提供并确认的公开 URL**；本材料是行为披露稿，不替代正式隐私政策 |
| 认证、审计或合规资质（如表单要求） | **待维护者提供实际凭证**；没有可确认材料时不声明已认证 |

官方提交文档要求联系邮箱和四项确认，但没有逐字列出四项确认内容。应在门户保留原文供维护者逐项阅读。来源与更新分支按第 1 节填写，自动发布开关由维护者根据更新策略选择。[官方提交说明][submit]

## 8. 提交材料的实际限制

- **展示来源范围**：门户读取指定插件目录中的清单和 README。本文件在 `docs/`，作为填写材料使用；仅把完整披露放在这里，不会自动使其显示在目录简介中。
- **凭据接入方式**：macOS 默认通知不需要凭据；可选网络渠道从本地 JSON 读取用户配置，当前清单没有 `userConfig`。官方提交清单要求凭据使用敏感配置字段。提交时需要如实说明当前文件配置方式，并根据门户对这一接入方式的反馈处理。
- **可审阅性限制**：通知脚本使用 shell 变量、命令替换、动态 `source`，并调用或加载其他脚本。官方清单将此类难以静态跟踪的执行路径列为可能需要人工审阅的情形；本材料不是门户通过结果。
- **数据保留限制**：完整事件日志默认开启，配置明文保存，日志和限流记录没有固定删除期限。取消排队不等于删除个人数据或撤回消息。
- **通知效果限制**：后续取消依赖宿主事件及时到达；渠道请求失败被忽略，代码没有交付确认或自动重试保证。
- **资产与声明状态**：图标已位于第 1 节列出的路径。18 岁以下受众、组织资格及四项确认需由维护者在门户填写。

官方依据：[提交说明][submit]、[提交前清单][checklist]。源码依据见第 3—6 节。

## 资料来源

官方材料仅采用：

- [Submit your plugin][submit]
- [Plugin pre-submission checklist][checklist]

仓库材料：

- [根 README][repo-readme]、[插件 README][plugin-readme]、[Claude 插件清单][manifest]、[MIT License][license]
- [通知调度器][notify]、[清理脚本][clear]、[提问分发脚本][pre-tool]、[消息格式化函数][format]
- [渠道脚本][channels]、[Claude hooks][hooks]、[配置模板][example]、[配置技能][config-skill]、[独立 Claude 安装器][installer]

[submit]: https://claude.com/docs/plugins/submit
[checklist]: https://claude.com/docs/plugins/pre-submission-checklist
[repo-readme]: ../README.md
[plugin-readme]: ../plugins/cc-notify-hooks/README.md
[manifest]: ../plugins/cc-notify-hooks/.claude-plugin/plugin.json
[license]: ../plugins/cc-notify-hooks/LICENSE
[notify]: ../plugins/cc-notify-hooks/scripts/notify.sh
[clear]: ../plugins/cc-notify-hooks/scripts/clear_pending.sh
[pre-tool]: ../plugins/cc-notify-hooks/scripts/pre_tool_use.sh
[format]: ../plugins/cc-notify-hooks/scripts/lib/notify_format.sh
[channels]: ../plugins/cc-notify-hooks/scripts/channels/
[hooks]: ../plugins/cc-notify-hooks/hooks/hooks.json
[example]: ../plugins/cc-notify-hooks/config/notify.example.json
[config-skill]: ../plugins/cc-notify-hooks/skills/config/SKILL.md
[installer]: ../install/claude.sh
