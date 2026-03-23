# cc-notify-hooks

Claude Code 分级推送通知系统。通过 hook 事件触发多渠道通知，用户响应后自动取消排队中的推送。

## 技术栈

- **语言**: Bash
- **依赖**: `jq`（JSON 解析）、`curl`（HTTP 请求）、`osascript`（macOS 通知）
- **集成**: Claude Code hooks 插件机制

## 项目结构

```
scripts/notify.sh          # 主调度器：事件过滤、延迟排队、渠道分发
scripts/clear_pending.sh   # 清除待发通知（用户交互时触发）
scripts/channels/*.sh      # 11 个渠道实现（macos/bark/telegram/pushover/ntfy/gotify/wechat/feishu/dingtalk/slack/discord）
hooks/hooks.json           # Claude Code hook 事件定义
config/notify.example.json # 配置模板
skills/config/SKILL.md     # 交互式配置 skill（/cc-notify-hooks:config）
install.sh                 # 交互式安装脚本（独立模式）
test_notify.sh             # 渠道连通性测试
```

## 常用命令

```bash
# 安装
bash install.sh

# 测试
bash test_notify.sh              # 测试所有已启用渠道
bash test_notify.sh bark         # 测试单个渠道
bash test_notify.sh list         # 列出已启用渠道
bash test_notify.sh hook         # 模拟完整 hook 流程

# 插件模式运行
claude --plugin-dir ./cc-notify-hooks
```

## 核心机制

- **分级延迟**: 短通知（秒级：macOS/Bark/Telegram）→ 长通知（分钟级：微信/飞书/钉钉/Slack）
- **Pending 取消**: 发送前创建标记文件，用户响应时清除，后台进程检查标记决定是否发送
- **速率限制**: 同类事件默认 10 秒内不重复推送
- **事件过滤**: 跳过子 agent、Stop 循环保护、/exit 静默

## 配置

路径: `~/.claude/hooks/notify.json` 或 `${CLAUDE_PLUGIN_DATA}/notify.json`

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

- 遵循 Claude Code 插件规范：skill 放 `skills/`，hook 放 `hooks/`，脚本放 `scripts/`
- 路径引用使用 `${CLAUDE_PLUGIN_ROOT}`（插件根目录）和 `${CLAUDE_PLUGIN_DATA}`（持久数据目录）
- 插件变更后用 `claude plugin validate .` 验证结构，用 `claude --plugin-dir .` 本地测试
- 测试 skill 交互时注意 AskUserQuestion 限制：每个问题 2-4 个选项，超出需分组

### 版本与发布

- 版本号遵循语义化版本（MAJOR.MINOR.PATCH）
- 更新版本号前必须向用户确认目标版本号，不得自行决定
- `plugin.json` 和 `marketplace.json` 中的版本号必须同步更新
- 功能变更须同步更新 README 相关章节
- 发布流程：commit → push → `gh release create vX.Y.Z`

### README 维护

- 新增功能必须更新 README 的对应章节（配置、文件结构等）
- 用户不一定需要重启 Claude Code，`/reload-plugins` 即可刷新插件

## 参考文档

- [Claude Code 插件开发指南](https://code.claude.com/docs/en/plugins.md)
- [Claude Code 插件参考](https://code.claude.com/docs/en/plugins-reference.md)
