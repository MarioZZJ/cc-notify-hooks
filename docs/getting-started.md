# 安装、更新与迁移

[← 项目首页](../README.md) · [配置通知](configuration.md) · [兼容性说明](compatibility.md)

本指南保留各入口的完整安装步骤。宿主版本、事件差异和市场分发依据见[兼容性说明](compatibility.md)；配置文件与通知内容见[配置指南](configuration.md)。也可将[纯文本安装指南](https://mariozzj.github.io/cc-notify-hooks/llms.txt)交给正在使用的 Agent，按当前环境完成接入。

## 依赖

执行通知脚本的环境需要 Bash、`jq` 和 `curl`。macOS 原生通知通过系统的 `osascript` 发送。

```bash
# macOS
brew install jq

# Debian / Ubuntu
sudo apt install jq curl
```

发送脚本运行在 Agent 或网关所在的环境。远程环境可配置手机推送与工作群消息；macOS 原生通知显示在运行该脚本的 Mac 上。

## Claude Code

### 插件市场安装

Claude Code 2.1.275 及以上可在会话中执行一条命令：

```text
/plugin install cc-notify-hooks --marketplace MarioZZJ/cc-notify-hooks
```

也可分别注册来源和安装：

```text
/plugin marketplace add MarioZZJ/cc-notify-hooks
/plugin install cc-notify-hooks@cc-notify-hooks
```

安装后运行 `/reload-plugins`，再执行 `/cc-notify-hooks:config` 启动配置向导。向导会选择渠道、填写凭据、设置延迟并提供连通性测试。

本仓库的 `.claude-plugin/marketplace.json` 指向 `plugins/cc-notify-hooks`。这是仓库提供的自建 marketplace，目录收录状态见[分发说明](compatibility.md#市场分发)。

### 从终端或 Agent 安装

支持插件管理的本地 shell 可直接执行：

```bash
claude plugin marketplace add MarioZZJ/cc-notify-hooks
claude plugin install cc-notify-hooks@cc-notify-hooks --scope user
```

已有 marketplace 时复用；已有安装时保留原范围，按后文更新。新安装示例使用当前用户范围；也可按需要选择 `project` 或 `local`。安装后用 `claude plugin list` 查看插件与范围，启动新会话或在已有会话中运行 `/reload-plugins` 加载。

这些是普通 shell 命令；`/plugin` 等斜杠命令只用于支持它们的交互会话，不能由 `claude -p` 执行。官方说明见[从 shell 安装](https://code.claude.com/docs/en/discover-plugins#install-from-your-shell)与[插件 CLI 参考](https://code.claude.com/docs/en/plugins/cli-reference)。

### Claude 本地插件模式

用于本地试用或开发，在终端执行：

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
claude --plugin-dir ./cc-notify-hooks/plugins/cc-notify-hooks
```

安装后的配置方法与插件市场方式相同。本地模式引用克隆目录，请保留目录。

## ChatGPT Codex

此入口要求运行环境支持本地插件与 hooks。安装使用 `codex` 命令；终端和桌面端分别提供 hooks 审阅入口。

```bash
codex plugin marketplace add MarioZZJ/cc-notify-hooks
codex plugin add cc-notify-hooks@cc-notify-hooks
```

仓库根目录的 `.agents/plugins/marketplace.json` 是插件来源，实际插件位于 `plugins/cc-notify-hooks/`。

安装后：

1. 启动新会话，在 `/hooks` 中审阅并信任 hooks；桌面端使用 **Settings > Hooks**。
2. 使用插件的 `config` 技能或 setup 入口配置通知。
3. 插件脚本更新后重新审阅 hooks，即使命令定义本身没有改变。

命令行 0.169.0 的 hooks 默认开启。若此前关闭过，在 `${CODEX_HOME:-~/.codex}/config.toml` 恢复：

```toml
[features]
hooks = true
```

`codex_hooks` 是旧版兼容别名。宿主支持范围与版本依据见[兼容性说明](compatibility.md#codex-cli)。

更新来源并同步插件：

```bash
codex plugin marketplace upgrade cc-notify-hooks
```

需要固定版本时，在添加 marketplace 来源时附加 `--ref <已发布的 tag>`；固定 tag 的来源更新仍跟随该 tag。

hook 命令以当前会话 `cwd` 执行。插件使用 `PLUGIN_ROOT` 定位脚本、`PLUGIN_DATA` 保存配置与状态，因此支持自定义 `CODEX_HOME`。开发时不要将 hook 路径写成相对于会话的 `./scripts/...`，也不要把用户凭据写入插件缓存。

## DeepSeek Harness

DeepSeek Harness 的命令为 `dsh`，插件包名为 `dsh-notify-hooks`。使用 0.2.2-rc.3 或更新的兼容版本。

### CLI profile

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh dsh web
```

安装器调用 `dsh plugin --profile <profile> add <仓库绝对路径>/plugins/cc-notify-hooks`，注册原生 Cordis 插件。配置文件为 `${DSH_HOME:-~/.dsh}/cc-notify-hooks/notify.json`，默认状态目录为同目录下的 `state`。

### 桌面版 profile

使用桌面版附带的 `dsh` 命令，先初始化 `desktop` profile，再在克隆目录中执行：

```bash
bash install.sh dsh desktop
```

普通 npm CLI 不能管理 `desktop` profile。未启用 HMR 时需重启对应宿主。本地安装引用仓库目录，安装后请保留。

### 自定义插件索引

在 **Experimental plugins** 中启用 **Custom plugin indexes**，进入 **Discover**，添加：

```text
https://mariozzj.github.io/cc-notify-hooks/dsh-index.json
```

选择 `dsh-notify-hooks`。当前索引固定到 v2.5.0 的发布提交，包目录为 `plugins/cc-notify-hooks`，具体来源见 [dsh-index.json](dsh-index.json)。

### 自定义配置位置

在对应 profile 的 `cordis.patch.yml` 中配置：

```yaml
- id: dsh-notify-hooks
  config:
    configFile: /absolute/path/notify.json
    stateDir: /absolute/path/state/dsh
```

已有配置中的 `stateDir` 继续生效。旧 home 级安装使用 `id: cc-notify-hooks`，字段相同；迁移规则见[更新与迁移](#更新与迁移)。

## Magpie

网关插件包名为 `agent-notify-hooks`，入口位于仓库根目录的 `package.json`。建议使用 0.1.4174 或更新的兼容版本。

### 使用安装器

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh magpie
```

安装器调用 `magpie plugin add <仓库绝对路径>`，绑定通知配置并设置 `gatewayTimeoutMs: 3000`。配置默认保存为 `~/.config/cc-notify-hooks/notify.json`，状态目录为同一插件目录下的 `state/magpie`。本地安装引用仓库目录，安装后请保留。

### 直接安装远程包

```bash
magpie plugin add github:MarioZZJ/cc-notify-hooks
```

也可从 Magpie 目录安装。包本身提供 `gatewayTimeoutMs: 3000`；直接安装时，如通知配置尚不存在，请将[配置模板](../plugins/cc-notify-hooks/config/notify.example.json)保存为 `~/.config/cc-notify-hooks/notify.json`，启用所需渠道并填写凭据。

### 自定义配置位置

```bash
magpie plugin options "<插件名或来源>" '{"configPath":"/absolute/path/notify.json","stateDir":"/absolute/path/state/magpie","gatewayTimeoutMs":3000}'
```

本地安装时，`<插件名或来源>` 使用安装命令中的仓库绝对路径。配置与状态目录可复用已有路径。

### 通知表示什么

插件通过异步 `onRequest` / `onResponse` 观察经过 Magpie 的模型请求，完整文本响应显示“模型响应完成”，请求错误显示“模型请求异常”。同会话下一次请求会清理之前的待发通知。

一次模型响应可能只是 Agent 多轮任务的一步。审批按钮、用户回答与客户端中断仍需原生 Agent 集成提供信息。没有会话 ID 或明确标记为子代理的网关请求会跳过；工具调用响应不作为完成通知。原生 hooks 与 Magpie 同时启用会分别通知。

本插件通过本地 JSON 配置渠道、延迟和摘要。Magpie 社区的 [Notify](https://github.com/magpie-community/plugins/tree/main/packages/notify) 提供另一套通知能力；任务时长筛选、账号掉线提醒和内嵌配置页面等差异可参考[兼容性资料](compatibility.md#magpie)及对方项目说明。

## 独立安装

Claude Code 和 ChatGPT Codex 均可通过安装器直接注册 hooks：

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh
```

也可指定目标：

```bash
bash install.sh claude
bash install.sh codex
```

安装器交互选择渠道、输入凭据并生成配置：

| 入口 | 通知配置 | hooks 配置 |
| --- | --- | --- |
| Claude Code | `~/.claude/hooks/notify.json` | 合并到 `~/.claude/settings.json` |
| ChatGPT Codex | `${CODEX_HOME:-~/.codex}/cc-notify-hooks/notify.json` | 合并到 `${CODEX_HOME:-~/.codex}/hooks.json` |

安装器保留其他插件的 hooks。安装后启动新会话；ChatGPT Codex 仍需在 `/hooks` 中审阅并信任。Claude Code 的 `/reload-plugins` 用于刷新插件模式。

## 更新与迁移

| 安装方式 | 更新时需要处理的事项 |
| --- | --- |
| Claude Code 插件 | 按宿主插件管理流程更新，再运行 `/reload-plugins` |
| ChatGPT Codex 插件 | `codex plugin marketplace upgrade cc-notify-hooks`；脚本变化后重新审阅 hooks |
| DeepSeek Harness 的 profile 插件 | 更新所引用的仓库后加载新模块；未启用 HMR 时重启宿主 |
| DeepSeek Harness 的旧 home 级安装 | 安装器识别 v2.4.0 的 `cc-notify-hooks` 条目，保留旧链接及配置，不重复注册 profile 插件；重启宿主加载新模块 |
| Magpie 本地插件 | 更新所引用的仓库，保留 `configPath` 与 `stateDir`；宿主按插件管理流程加载 |
| Claude / ChatGPT Codex 独立安装 | 在更新后的仓库中再次执行对应安装器，按提示保留或调整配置；安装器仅替换本安装目录所属的 hook 处理器 |

DeepSeek Harness 的旧兼容链接为 `~/node_modules/@dsh-local/dsh-cc-notify`，旧注册项位于 `${DSH_HOME:-~/.dsh}/cordis.patch.yml`。旧配置继续编辑 `id: cc-notify-hooks`；新 profile 安装使用 `id: dsh-notify-hooks`。

DeepSeek Harness 与 Magpie 的安装器只在配置文件不存在时创建模板，已有配置保留。

## 验证安装

在本地仓库先查看启用的渠道：

```bash
bash test_notify.sh list
```

需要验证真实送达时，再测试已配置渠道：

```bash
bash test_notify.sh bark
bash test_notify.sh
```

第一条测试指定渠道，第二条测试所有已启用渠道，均会尝试发送真实通知。模板、会话隔离、宿主适配等开发检查见[测试与验证](development.md#测试与验证)。

## 卸载

| 安装方式 | 操作 |
| --- | --- |
| Claude Code 插件 | 在 `/plugin` 中管理和卸载 |
| ChatGPT Codex 插件 | 在 `/plugins` 中管理，或执行 `codex plugin remove cc-notify-hooks@cc-notify-hooks` |
| DeepSeek Harness profile 插件 | `dsh plugin --profile <profile> remove dsh-notify-hooks` |
| Magpie | `magpie plugin rm "<插件名或来源>"` |

DeepSeek Harness 的旧 home 级安装需要从 `${DSH_HOME:-~/.dsh}/cordis.patch.yml` 删除本插件的 `cc-notify-hooks` 条目，再移除 `~/node_modules/@dsh-local/dsh-cc-notify` 兼容链接。

Claude Code 独立安装：从 `~/.claude/settings.json` 移除本插件的 hook 处理器，再清理本插件安装在 `~/.claude/hooks/scripts` 中的脚本及自己的 `notify.json`、状态文件。若该目录同时放有其他 hooks，保留它们的文件。

ChatGPT Codex 独立安装：从 `${CODEX_HOME:-~/.codex}/hooks.json` 移除本插件的处理器，再清理 `${CODEX_HOME:-~/.codex}/cc-notify-hooks` 中的本插件文件。自定义 `CODEX_HOME` 时使用对应目录。

如需保留通知渠道与凭据供重装使用，先保留自己的 `notify.json`。
