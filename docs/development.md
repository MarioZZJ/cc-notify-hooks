# 开发与排错

[← 项目首页](../README.md) · [安装指南](getting-started.md) · [配置指南](configuration.md) · [网页开发](website.md)

核心发送脚本使用 Bash，DeepSeek Harness 与 Magpie 的原生适配使用 JavaScript。依赖为 Bash、`jq`、`curl`；macOS 原生通知使用 `osascript`。

## 调度过程

1. **接收并归一事件。** 原生宿主 hooks、DeepSeek Harness 拦截点或 Magpie 网关回调提供事件，`notify.sh` 提取会话、项目、摘要等字段。
2. **过滤并建立队列。** 按会话与事件类别处理去重，创建待发标记；启用的渠道经过 `events` 筛选后，按延迟排序。
3. **到时再次检查。** 后台任务到达渠道延迟时检查待发标记；仍存在才调用发送脚本。
4. **宿主活动取消待发。** 新输入、提问结束或适配支持的其他事件调用 `clear_pending.sh`，清理相应会话或请求的标记。

例如同一事件可在 3 秒触发 macOS、5 秒触发 Telegram、15 秒触发手机推送、300 秒触发工作群消息。每个渠道的计时起点相同，均为插件收到事件。若先前处理已经清理标记，后续渠道跳过发送；送达的消息不会撤回。

`pre_tool_use.sh` 识别 `AskUserQuestion`、`request_user_input` 等提问工具。提问通知保留调用 ID，工具结束后可以定向清理。

DeepSeek Harness 可以同时等待多个审批，因此其权限／输入通知按请求 ID 保留；其他常规事件会清理当前会话的旧待发标记再创建新标记。取消与版本边界见[事件覆盖说明](configuration.md#事件覆盖与取消)。

## 过滤规则

| 规则 | 行为 |
| --- | --- |
| 子代理过滤 | 原生脚本跳过非空 `agent_id`；DeepSeek Harness 检查 `session.header.origin`；Magpie 检查 `ctx.kind` |
| Stop 循环保护 | `stop_hook_active=true` 时跳过 `stop` 通知 |
| `/exit` 静默 | 仅抑制当前会话随后的一次 Stop 通知 |
| 速率限制 | 按会话与事件类别隔离，默认窗口为 10 秒；结构化问题及有调用 ID 的审批按调用去重 |
| Magpie 事件筛选 | 缺少会话 ID 时跳过；完整文本终结响应可通知，工具调用响应不作为完成消息 |

默认状态目录为 `${PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/hooks}}/state`，可由 `CC_NOTIFY_STATE_DIR` 覆盖。原生适配和独立安装器会传入对应状态路径，具体位置见[安装指南](getting-started.md)。

## 渠道接口

每个 `scripts/channels/*.sh` 定义对应的 `send_<channel>` 函数，参数依次为标题、短正文、渠道配置 JSON、归一事件 JSON。长通知渠道使用事件 JSON 生成结构化卡片；短通知渠道通常使用标题与正文。

渠道失败不阻断其他渠道。发送调用有容错处理，各 HTTP 请求使用 `curl` 的超时限制。没有配置文件时，仅 macOS 的 `notification` 事件提供默认系统通知；其他平台安静退出。

通知格式的共同处理位于 `scripts/lib/notify_format.sh`。涉及通知字段的修改应同时核对[配置指南的通知内容](configuration.md#通知内容)和模板测试。

## 文件结构

| 路径 | 用途 |
| --- | --- |
| `package.json` | Magpie 包 `agent-notify-hooks`，声明 `magpie.hooks` |
| `adapters/magpie/hooks.mjs` | Magpie 的 `onRequest` / `onResponse` |
| `.claude-plugin/marketplace.json` | Claude Code 自建 marketplace，指向插件子目录 |
| `.agents/plugins/marketplace.json` | ChatGPT Codex 自建 marketplace，指向插件子目录 |
| `plugins/cc-notify-hooks/` | Claude Code 与 ChatGPT Codex 的真实插件根目录 |
| `plugins/cc-notify-hooks/.claude-plugin/plugin.json` | Claude Code 插件清单 |
| `plugins/cc-notify-hooks/.codex-plugin/plugin.json` | ChatGPT Codex 插件清单及配置技能入口 |
| `plugins/cc-notify-hooks/package.json` | DeepSeek Harness 的 `dsh-notify-hooks` 包 |
| `plugins/cc-notify-hooks/dsh-plugin/` | DeepSeek Harness 原生事件模块与 `cordis.patch.yml` |
| `plugins/cc-notify-hooks/reasonix-plugin.json` | 保留的 Reasonix 原生插件兼容清单 |
| `plugins/cc-notify-hooks/hooks/hooks.json` | Claude Code hooks |
| `plugins/cc-notify-hooks/hooks/codex-hooks.json` | ChatGPT Codex hooks |
| `plugins/cc-notify-hooks/scripts/notify.sh` | 事件过滤、归一与延迟分发 |
| `plugins/cc-notify-hooks/scripts/clear_pending.sh` | 清理会话或请求的待发标记 |
| `plugins/cc-notify-hooks/scripts/pre_tool_use.sh` | 工具事件与结构化提问分发 |
| `plugins/cc-notify-hooks/scripts/channels/` | 11 个渠道的发送实现 |
| `plugins/cc-notify-hooks/config/notify.example.json` | 完整配置模板 |
| `plugins/cc-notify-hooks/skills/config/SKILL.md` | 交互式配置技能 |
| `plugins/cc-notify-hooks/README.md` | 插件包及目录提交说明 |
| `plugins/cc-notify-hooks/test_notify.sh` | 连通性、模板、会话状态与宿主字段检查 |
| `install.sh` | 独立安装路由 |
| `install/claude.sh` / `install/codex.sh` | 对应宿主的独立安装器 |
| `install/dsh.sh` / `install/native.sh` | DeepSeek Harness 与 Magpie 原生安装入口 |
| `install/reasonix.sh` | 保留的 Reasonix 安装兼容入口 |
| `docs/` | 项目网站、演示、插件索引与参考文档 |

根目录的 `scripts`、`hooks`、`config`、`skills` 和 `test_notify.sh` 为插件子目录的软链接；根目录 `.claude-plugin/plugin.json` 与 `.codex-plugin/plugin.json` 也链接到对应插件清单。

ChatGPT Codex 的 hook 在当前会话 `cwd` 执行，必须通过 `PLUGIN_ROOT` 定位脚本、`PLUGIN_DATA` 保存用户数据。Claude Code 对应使用 `CLAUDE_PLUGIN_ROOT` 与 `CLAUDE_PLUGIN_DATA`。

## 测试与验证

从仓库根目录运行。先按改动范围选择检查，纯网页或文档变更通常不需要发送真实通知。

### 本地逻辑检查

```bash
bash test_notify.sh list
bash test_notify.sh codex-plugin-hooks
bash test_notify.sh user-input
bash test_notify.sh state
bash test_notify.sh render
bash test_notify.sh agents
node plugins/cc-notify-hooks/dsh-plugin/test/plugin.test.mjs
```

| 命令参数 | 核对内容 |
| --- | --- |
| `list` | 当前启用的渠道与延迟 |
| `codex-plugin-hooks` | 插件脚本从任意会话目录解析运行时路径 |
| `user-input` | `request_user_input` 分发、短／长通知字段与缺少依赖时的行为 |
| `state` | 多会话状态隔离与精确去重 |
| `render` | 通知模板及统一事件字段 |
| `agents` | 保留的 Reasonix、DeepSeek Harness 识别与环境变量覆盖顺序 |

### 真实通知与 hook 流程

以下命令会使用已配置渠道尝试发送消息：

```bash
bash test_notify.sh
bash test_notify.sh bark
bash test_notify.sh hook
bash test_notify.sh codex
```

无参数时测试所有已启用渠道；指定渠道时只测试该渠道。`hook` 模拟 Claude Code 通知，`codex` 模拟 ChatGPT Codex 的 `PermissionRequest`，二者会按配置延迟排队。

需要手动核对通知模板而不发送时，可用 `CC_NOTIFY_RENDER_ONLY=1` 向脚本提供事件 JSON。相关现成样例位于 `test_notify.sh` 的 `render` 与 `user-input` 检查中。

网页的主题、播放控制、静态审阅入口及本地服务器步骤见[网页开发说明](website.md)。

## 排查问题

调试日志位于 `/tmp/claude-hooks-debug.log`，包含收到的事件 payload。检查或分享日志时，仅保留与问题有关的字段。

| 现象 | 先检查什么 |
| --- | --- |
| 完全没有通知 | hook 是否加载并受信任，Bash／`jq`／`curl` 是否可用，实际生效配置的位置 |
| 有等待提醒，没有完成提醒 | 对应渠道的 `events` 是否包含 `stop`；Magpie 网关事件应使用 `notification` |
| macOS 通知出现在另一台机器 | 脚本运行在哪台 Mac；远程宿主使用推送渠道更直接 |
| 延迟比配置值长 | 宿主发出事件前可能已有等待；插件从接收事件起计时 |
| 看过通知后仍收到后续提醒 | 仅查看通知不产生取消信号，需宿主报告后续输入或支持的活动 |
| 更新后通知停止 | ChatGPT Codex 是否重新信任 hooks；相应宿主是否加载了新插件模块 |
| 一次操作出现两类通知 | 是否同时启用了原生 Agent hooks 和 Magpie 网关插件 |

## 插件分发

| 入口 | 分发方式与参考 |
| --- | --- |
| Claude Code | 仓库自建 marketplace；官方目录提交使用开发者门户，材料与收录跟踪见 [#5](https://github.com/MarioZZJ/cc-notify-hooks/issues/5) |
| ChatGPT Codex | 仓库自建 marketplace；公共目录对生命周期 hooks 的限制以[兼容性说明](compatibility.md#市场分发)记录的依据为准 |
| DeepSeek Harness | [自定义索引](https://mariozzj.github.io/cc-notify-hooks/dsh-index.json)，包名 `dsh-notify-hooks`，固定发布提交与插件子目录 |
| Magpie | 根包 `agent-notify-hooks`，通过 `magpie.hooks` 接入；仓库使用 `magpie-plugin` topic，社区列表状态见 #5 |

版本依据、来源与市场规则集中维护于[兼容性说明](compatibility.md)，开发者门户填写内容、数据处理说明及账号声明见[目录提交材料](marketplace-submission.md)。发行版本见 [Releases](https://github.com/MarioZZJ/cc-notify-hooks/releases)。
