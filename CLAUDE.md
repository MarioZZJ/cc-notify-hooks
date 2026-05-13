# cc-notify-hooks

Claude Code 与 Codex CLI 的分级推送通知系统。通过 hook 事件触发多渠道通知，用户响应后自动取消排队中的推送。

## 技术栈

- **语言**: Bash
- **依赖**: `jq`（JSON 解析）、`curl`（HTTP 请求）、`osascript`（macOS 通知）
- **集成**: Claude Code 与 Codex CLI 的 hooks 插件机制

## 项目结构

```
scripts/notify.sh           # 主调度器：事件过滤、延迟排队、渠道分发（兼容 Claude/Codex 字段）
scripts/clear_pending.sh    # 清除待发通知（用户交互时触发）
scripts/channels/*.sh       # 11 个渠道实现（macos/bark/telegram/pushover/ntfy/gotify/wechat/feishu/dingtalk/slack/discord）
hooks/hooks.json            # Claude Code hook 事件定义
hooks/codex-hooks.json      # Codex CLI hook 事件定义（PermissionRequest/Stop/UserPromptSubmit/PreToolUse）
.claude-plugin/             # Claude Code 插件清单 + marketplace
.codex-plugin/              # Codex CLI 插件清单
.agents/plugins/            # Codex CLI marketplace
config/notify.example.json  # 配置模板
skills/config/SKILL.md      # 交互式配置 skill（/cc-notify-hooks:config，Claude Code 专属）
install.sh                  # 独立安装入口（路由）
install/claude.sh           # Claude Code 安装分支
install/codex.sh            # Codex CLI 安装分支
test_notify.sh              # 渠道连通性测试
```

## 常用命令

```bash
# 安装
bash install.sh                  # 交互式选择 Claude Code 或 Codex
bash install.sh claude           # 直接装到 Claude Code
bash install.sh codex            # 直接装到 Codex CLI

# 测试
bash test_notify.sh              # 测试所有已启用渠道
bash test_notify.sh bark         # 测试单个渠道
bash test_notify.sh list         # 列出已启用渠道
bash test_notify.sh hook         # 模拟 Claude Code hook 流程
bash test_notify.sh codex        # 模拟 Codex CLI PermissionRequest 事件

# 插件模式运行
claude --plugin-dir ./cc-notify-hooks
```

## 核心机制

- **分级延迟**: 短通知（秒级：macOS/Bark/Telegram）→ 长通知（分钟级：微信/飞书/钉钉/Slack）
- **Pending 取消**: 发送前创建标记文件，用户响应时清除，后台进程检查标记决定是否发送
- **速率限制**: 同类事件默认 10 秒内不重复推送
- **事件过滤**: 跳过子 agent、Stop 循环保护、/exit 静默

## 配置

配置文件查找顺序（`scripts/notify.sh` 实现）:
1. `${CC_NOTIFY_CONFIG}`（手动覆盖）
2. `${CLAUDE_PLUGIN_DATA}/notify.json`（Claude 插件模式）
3. `~/.codex/cc-notify-hooks/notify.json`（Codex 独立模式）
4. `~/.claude/hooks/notify.json`（Claude 独立模式）

```json
{
  "channels": {
    "channel_name": {
      "enabled": true,
      "delay": 3,
      "events": ["notification", "stop"]
    }
  },
  "rate_limit": 10
}
```

## 开发注意

- 所有渠道脚本遵循相同接口：接收 `$1`=标题 `$2`=内容，从环境变量/配置读取凭据
- 渠道发送用 `|| true` 包裹，单个失败不影响其他渠道
- 无配置文件时 macOS 用户自动降级为系统通知

## 开发规范

### 插件开发

**Claude Code**:
- 清单 `.claude-plugin/plugin.json`，hook 配置 `hooks/hooks.json`
- 路径引用 `${CLAUDE_PLUGIN_ROOT}`（插件根）和 `${CLAUDE_PLUGIN_DATA}`（持久数据）
- 插件变更后 `claude plugin validate .` 验证，`claude --plugin-dir .` 本地测试
- skill 交互注意 AskUserQuestion 限制：每个问题 2-4 个选项

**Codex CLI**:
- 清单 `.codex-plugin/plugin.json`，hook 配置 `hooks/codex-hooks.json`
- Codex hook 命令以会话 `cwd` 执行，不能用 `./scripts/...`；插件模式需从 `~/.codex/plugins/cache/*/cc-notify-hooks/*/` 定位脚本
- Marketplace `.agents/plugins/marketplace.json`，policy 必填 installation/authentication/category
- 启用 hooks 需要 `~/.codex/config.toml` 添加 `[features]\ncodex_hooks = true`
- 字段差异：Codex `prompt` ↔ Claude `message`（已在脚本里 fallback），Codex 无 Notification 事件（用 PermissionRequest 替代）

**两边共用**:
- 渠道脚本接口：`$1`=标题 `$2`=内容，从环境变量/配置读取凭据
- 渠道发送 `|| true` 包裹，单个失败不影响其他渠道

### 版本与发布

- 版本号遵循语义化版本（MAJOR.MINOR.PATCH）
- 更新版本号前必须向用户确认目标版本号，不得自行决定
- 四份清单同步更新版本号：`.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`、`.codex-plugin/plugin.json`、`.agents/plugins/marketplace.json`
- 功能变更须同步更新 README 与 `docs/index.html`（GitHub Pages）
- 发布流程：commit → push → `gh release create vX.Y.Z`

### README 维护

- 新增功能必须更新 README 的对应章节（配置、文件结构等）
- 用户不一定需要重启 Claude Code，`/reload-plugins` 即可刷新插件

## 参考文档

- [Claude Code 插件开发指南](https://code.claude.com/docs/en/plugins.md)
- [Claude Code 插件参考](https://code.claude.com/docs/en/plugins-reference.md)
- [Codex Hooks 文档](https://developers.openai.com/codex/hooks)
- [Codex 配置参考](https://developers.openai.com/codex/config-reference)
