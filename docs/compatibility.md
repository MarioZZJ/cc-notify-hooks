# Agent 与插件分发兼容性

核对日期：2026-11-14。特性与事件适配跟踪于 [#4](https://github.com/MarioZZJ/cc-notify-hooks/issues/4)，安装注册与市场收录跟踪于 [#5](https://github.com/MarioZZJ/cc-notify-hooks/issues/5)。

**v2.5.0** 基于 v2.4.0（2026-08-18 发布）更新；后者已包含 dsh 原生插件。本版本升级既有 dsh 实现并新增 Magpie 入口。来源：[v2.5.0 发布记录](https://github.com/MarioZZJ/cc-notify-hooks/releases/tag/v2.5.0)。

## 版本基准

| 工具 | 本次核对的最新发布 | 发布时间（北京时间） | 依据 |
|---|---|---|---|
| Claude Code | 2.1.325 | 2026-11-14 04:40 | [官方发布](https://github.com/anthropics/claude-code/releases/tag/v2.1.325) |
| Codex CLI | 0.169.0 | 2026-11-13 16:37 | [官方发布](https://github.com/openai/codex/releases/tag/rust-v0.169.0) |
| DeepSeek Harness（dsh） | 0.2.2-rc.3，预发布 | 2026-11-13 15:56 | [官方发布](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.2.2-rc.3) |
| Magpie | 0.1.4174 | 2026-11-14 19:58 | [官方发布](https://github.com/yetone/magpie/releases/tag/v0.1.4174) |

Magpie 的网关接口依据 0.1.4173 源码；0.1.4174 沿用该 hook 契约与插件加载接口。表中版本用于定位适配依据。

## 事件与调整

### Claude Code

现有 `Notification`、`Stop`、`UserPromptSubmit` 和工具 hooks 仍受支持。增加 `AskUserQuestion` 的 `PreToolUse` 路由，在工具结束或失败后定向取消提问通知；`StopFailure` 使用异常通知；`SessionEnd` 清理当前会话队列。`Notification.elicitation_dialog` 对应 MCP 输入表单，继续保留。

`PreToolUse` 发生在权限确认之前。`PostToolUse`、`PostToolUseFailure` 可以清理执行后的通知，但后者不覆盖执行前的权限拒绝。因而 Claude 的权限通知不能承诺在用户点击按钮时立即取消。`permission_prompt` 通常在宿主等待约 6 秒后发出，`idle_prompt` 通常在约 60 秒后发出；渠道配置中的延迟从插件收到事件开始计算。

依据：[Hooks](https://code.claude.com/docs/en/hooks)、[AskUserQuestion](https://code.claude.com/docs/en/tools-reference#askuserquestion-tool-behavior)。

### Codex CLI

hooks 已稳定并默认开启，正式配置键为 `[features].hooks`；`codex_hooks` 是弃用别名。插件继续用 `.codex-plugin/plugin.json` 指定 `hooks/codex-hooks.json`，命令使用 `PLUGIN_ROOT`、数据使用 `PLUGIN_DATA`。

保留 `request_user_input` 的 `PreToolUse` / `PostToolUse` 路径，增加 `Interrupt` 和 `SessionEnd` 清理，并在工具完成后清理待发权限通知。`SessionEnd`、`Interrupt` 的超时设置为 3 秒，符合当前上限。

`PermissionRequest` 仍在 Guardian 自动审阅或人工审批之前运行，payload 没有“人工正等待”的精确信号。不能根据 `permission_mode` 直接跳过全部事件，否则可能漏报转交人工的审批。[#3](https://github.com/MarioZZJ/cc-notify-hooks/issues/3) 继续保留；增加延迟只能减少短暂审批的推送，不能准确识别审批处理者。

安装或更新后必须审阅 hooks。当前信任还覆盖插件脚本，脚本变化会重新触发审阅；CLI 使用 `/hooks`，桌面端使用 Settings > Hooks。

依据：[Hooks](https://learn.chatgpt.com/docs/hooks)、[0.169.0 功能开关](https://github.com/openai/codex/blob/rust-v0.169.0/codex-rs/features/src/lib.rs)、[审批事件实现](https://github.com/openai/codex/blob/rust-v0.169.0/codex-rs/hooks/src/events/permission_request.rs)。

### DeepSeek Harness

dsh 为 `deepseek-ai/deepseek-harness`。其官方 Claude hook 桥接只支持七种事件：`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`Stop`、`SubagentStart`、`SubagentStop`；不支持 `PermissionRequest` 和 `Notification`。直接复用 Claude 的配置会缺少权限等待通知。

本插件升级既有 `plugins/cc-notify-hooks/dsh-plugin/index.js` 原生 Cordis 模块。原实现订阅 `agent/turn-stopping` 时回合仍可能被继续，因此改用最终 `turn/end`；同时保留 `scriptsDir`、`configFile`、`stateDir` 配置及最终回复摘要：

- `session/event` 中的 `approval/asked` / `approval/decided` 按请求 id 排队和取消权限通知。
- `user-questions/request` 在等待期间排队提问通知，始终透传 `next()` 的结果，结束或取消后清理；审批同时显示为问题卡时避免重复通知。
- `turn/end.reason.kind` 为 `completed` 才显示任务完成；`error`、`max-tokens`、`blocked` 显示异常；取消等其他结束原因只清理通知。
- 输入进入 inbox、新回合开始、Agent 销毁或插件卸载时清理队列。
- 使用 `session.header.origin === "subagent"` 过滤子代理，使用会话的 `workingDirectory`，不把宿主进程目录当成所有会话的工作目录。

`plugins/cc-notify-hooks/package.json` 声明包名 **`dsh-notify-hooks`**、`dsh.manifestVersion: 1` 与 `dsh.bundle.patch`。包包含原生事件模块、通知脚本和配置模板；`dsh-plugin/cordis.patch.yml` 通过 `./index.js` 加载模块，新条目 id 为 `dsh-notify-hooks`。已有 home 级安装保留旧链接及 `cc-notify-hooks` 配置条目作为兼容入口，新安装使用 profile 插件管理器。仓库根包单独作为 Magpie 插件，不再声明 dsh bundle。

依据：[Claude 桥接实现](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.2-rc.3/packages/experimental/hooks-claude-code/src/index.ts)、[会话与结束原因](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.2-rc.3/packages/core/session/src/types.ts)、[审批事件](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.2-rc.3/packages/interaction/user-approval/src/types.ts)、[问题接口](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.2-rc.3/packages/interaction/user-questions/src/types.ts)、[Cordis 事件](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.2-rc.3/docs/cordis-api/events.md)。

### Magpie

Magpie 为 `yetone/magpie`。本插件的 Magpie 包名为 **`agent-notify-hooks`**，通过根目录 `package.json` 的 `magpie.hooks` 接入异步网关 hook，导出 `onRequest` 和 `onResponse`。同步 `magpie.middleware` 不提供本插件所需的 Node 进程接口。

网关事件仅覆盖经过 Magpie 的模型请求：

- 新请求清理该会话此前的网关通知。
- 完整成功且可识别为文本终结响应的回复，显示“模型响应完成”；工具调用响应不显示为完成。
- 请求失败显示“模型请求异常”。
- `ctx.kind === "subagent"` 时跳过；缺少 `ctx.session` 时跳过，避免不同请求共用未知会话队列。
- 不把网关请求称为用户提交，也不把单次模型响应称为 Agent 任务完成。审批 UI、用户回答和客户端中断仍需原生 Agent 集成。

默认 callback 超时为 1 秒；本项目安装器设置 `gatewayTimeoutMs: 3000`。回调只将通知交给本地脚本，分钟级延迟在后台处理。原生 Agent hooks 与 Magpie 插件同时启用可能产生两种通知，按希望观察的层次选择安装入口。

依据：[网关 hook 契约](https://github.com/yetone/magpie/blob/v0.1.4173/docs/subsystems/gateway-request-hooks.md)、[加载与回调执行](https://github.com/yetone/magpie/blob/v0.1.4173/internal/plugin/host.js)、[官网插件指南](https://usemagpie.ai/docs/plugins#gateway-request)。

## 安装与注册

| 工具 | 当前入口 | 仓库中的实现 |
|---|---|---|
| Claude Code | 2.1.275 起可用 `/plugin install cc-notify-hooks --marketplace MarioZZJ/cc-notify-hooks` | `.claude-plugin/marketplace.json` 指向 `plugins/cc-notify-hooks` |
| Codex | `codex plugin marketplace add MarioZZJ/cc-notify-hooks`，再 `codex plugin add cc-notify-hooks@cc-notify-hooks` | `.agents/plugins/marketplace.json` 与插件内 `.codex-plugin/plugin.json` |
| dsh | `dsh plugin --profile <profile> add <仓库绝对路径>/plugins/cc-notify-hooks` | `dsh-notify-hooks` 包、`dsh-plugin/cordis.patch.yml` |
| Magpie | `magpie plugin add <仓库绝对路径>` 或 `magpie plugin add github:MarioZZJ/cc-notify-hooks` | 根包 `agent-notify-hooks` 的 `magpie.hooks` |

dsh 桌面版附带命令可管理已初始化的 `desktop` profile；普通 npm CLI 不支持管理该 profile。`web` 等 CLI profile 单独安装。安装器遇到 v2.4.0 的 home 级条目时只更新原插件链接，避免 home 补丁和新 bundle 重复加载通知模块。配置继续使用 `${DSH_HOME:-~/.dsh}/cc-notify-hooks/notify.json`，保留旧配置字段。未启用 HMR 时重启对应宿主。

Claude 和 Codex 的独立安装器现在复制完整脚本目录，使用可兼容 macOS 默认 Bash 的 JSON 配置处理，只替换本安装目录所属的 hooks，并保留其他插件的同名事件处理器。

依据：[Claude 安装命令](https://code.claude.com/docs/en/discover-plugins#add-a-marketplace-and-install-in-one-command)、[Codex 包与 marketplace](https://developers.openai.com/plugins/build/plugins)、[dsh CLI](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.2-rc.3/apps/cli/README.md)、[Magpie 插件注册](https://github.com/yetone/magpie/blob/v0.1.4173/internal/plugin/store.go)。

## 市场分发

| 工具 | 已确认的机制 | 本项目的发布要求 |
|---|---|---|
| Claude | 自建 marketplace 与官方目录分别管理；第三方通过开发者门户提交 | 已提供插件目录 README。发布新版本后通过门户填写仓库子目录、图标等审核材料 |
| Codex | 自建 Git / 本地 marketplace 继续可用；含生命周期 hooks 的包目前不允许提交公共目录 | 继续自建 marketplace 分发，跟踪官方资格限制 |
| dsh | 实验性的 Custom plugin indexes；没有预置索引源 | [自定义索引](https://mariozzj.github.io/cc-notify-hooks/dsh-index.json) 已提供 v2.5.0 的版本、发布时间和提交，包名为 `dsh-notify-hooks` |
| Magpie | 社区插件列表与 GitHub topic 发现 | `agent-notify-hooks` 根包已发布，仓库已添加 `magpie-plugin` topic；社区列表申请继续由 #5 跟踪 |

自建 marketplace 的可安装状态不代表官方已收录。

本次查询的 Claude 官方和社区目录均未收录 `cc-notify-hooks`：分别检查了官方仓库提交 `b5b01ac4f889`、社区仓库提交 `163301d1904c` 的完整目录树和 `.claude-plugin/marketplace.json`，名称及来源均无匹配。对应目录快照：[官方](https://github.com/anthropics/claude-plugins-official/blob/b5b01ac4f889fec0c4c6bb89f27ca7c8574473f6/.claude-plugin/marketplace.json)、[社区](https://github.com/anthropics/claude-plugins-community/blob/163301d1904c0a994539f5226ce0fcd65b8652bf/.claude-plugin/marketplace.json)。

发布后的索引、目录申请和发现步骤统一跟踪在 [#5](https://github.com/MarioZZJ/cc-notify-hooks/issues/5)。

Claude 官方仓库不再监看第三方插件 PR，社区仓库是审核结果的只读镜像；提交入口为 [开发者门户](https://claude.ai/directory/manage)。目录图标需要方形 PNG/JPEG，512–2048 px，小于 2 MB。

dsh 索引的 Git 来源要求完整 40 位 commit；本项目的索引使用 `name: dsh-notify-hooks`、`source.path: plugins/cc-notify-hooks`，固定到 v2.5.0 的发布提交 `2f317215c2ab3525746896a4196f513ade0548d2`。索引发布在 [GitHub Pages](https://mariozzj.github.io/cc-notify-hooks/dsh-index.json)。

依据：[Claude 官方仓库](https://github.com/anthropics/claude-plugins-official)、[社区仓库](https://github.com/anthropics/claude-plugins-community)、[提交要求](https://claude.com/docs/plugins/pre-submission-checklist)、[OpenAI 对 hooks 的公共目录限制](https://developers.openai.com/plugins/build/plugins#bundled-mcp-servers-and-lifecycle-hooks)、[dsh 索引格式](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.2-rc.3/docs/user/guide/plugin-market.md)、[Magpie 插件发现](https://github.com/yetone/magpie/blob/v0.1.4173/site/public/docs/plugins.html)。
