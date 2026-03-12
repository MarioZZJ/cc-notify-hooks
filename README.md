# Claude Code 分级推送通知

Claude Code 事件推送通知，支持 macOS 和 Linux。

- **macOS 本地**：立即弹系统原生通知，零配置
- **Linux/远程**：Bark（桌面）+ 企业微信（手机）分级延迟推送

## 工作原理

```
Claude Code 事件触发
        │
        ▼
  notify.sh 清除旧 pending → 创建新 pending
        │
        ├── [macOS] 立即 ──→ 系统原生通知（osascript）
        │
        ├── 15s 后 ──→ pending 存在？──→ 🔔 Bark
        │                  └── 不存在 ──→ 跳过
        │
        └── 5min 后 ──→ pending 存在？──→ 💬 企业微信
                           └── 不存在 ──→ 跳过

  取消推送的 3 种方式：
  ├── 新事件覆盖旧 pending
  ├── 用户发消息 → clear_pending.sh 清全部
  └── 推送完成后自动清理
```

## 监听的事件

| Hook | 触发时机 | 通知内容 |
|------|---------|---------|
| **Notification `*`** | 权限确认、AskUserQuestion 等 | 👋 需要你的注意 |
| **Stop `*`** | Claude 回复结束 | ✅ 任务完成 |
| **UserPromptSubmit `*`** | 用户发消息 | （清除 pending，不推送） |

通知正文格式：`[项目名|权限模式] 事件描述`

## 安装

### 前置依赖

```bash
# macOS
brew install jq

# Debian/Ubuntu
sudo apt install -y jq curl

# CentOS/RHEL
sudo yum install -y jq curl
```

### 设置环境变量

macOS 本地使用无需任何环境变量，系统通知开箱即用。

远程推送（Bark/企业微信）需要在 `~/.bashrc` 或 `~/.zshrc` 中添加：

```bash
export BARK_KEY="你的-bark-key"
export QYWX_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的key"

# 可选
# export BARK_SERVER="https://your-bark-server.com"  # 自建 Bark 服务器
# export BARK_DELAY=15     # Bark 推送延迟（秒）
# export WECHAT_DELAY=300  # 企业微信推送延迟（秒）
```

### 运行安装脚本

```bash
bash install.sh
```

安装脚本会自动检测环境：
- **macOS**：提示系统原生通知已就绪，远程推送凭证为可选
- **有 cc-switch**：将 hooks 配置合并到 cc-switch 的 common config，切换 provider 不丢失
- **无 cc-switch**：直接合并到 `~/.claude/settings.json`（自动备份原配置）

#### cc-switch 用户注意

hooks 的执行环境可能拿不到 `~/.bashrc` 中的变量。如果推送不生效，需要将凭证写入 cc-switch 的 env：

```bash
cc-switch env set BARK_KEY "your-bark-key" -a claude
cc-switch env set QYWX_WEBHOOK "https://..." -a claude
```

### 测试

```bash
bash test_notify.sh all     # 测试 Bark + 企业微信
bash test_notify.sh bark    # 仅测试 Bark
bash test_notify.sh wechat  # 仅测试企业微信
bash test_notify.sh hook    # 模拟完整 hook 流程（含延迟）
```

### 重启 Claude Code

Hooks 配置在启动时加载，安装后需重启 Claude Code 生效。

## 过滤规则

- **子智能体事件**：跳过（`agent_id` 非空时不推送）
- **Stop hook 循环保护**：`stop_hook_active=true` 时跳过
- **防重复**：同类事件 10 秒内只推一次

## 文件说明

```
项目目录/
├── notify.sh          # 核心推送脚本（macOS/Linux 自适应）
├── clear_pending.sh   # 响应清除脚本
├── settings.json      # hooks 配置模板
├── install.sh         # 安装脚本（兼容 macOS/Linux/cc-switch）
├── test_notify.sh     # 连通性测试脚本
└── README.md

安装后：
~/.claude/hooks/
├── notify.sh
├── clear_pending.sh
└── state/
    ├── pending_*      # 待推送标记
    └── last_*         # 防重复时间戳

调试日志：/tmp/claude-hooks-debug.log
```

## 获取推送凭证

### Bark

打开 Mac 上的 Bark app，首页显示推送 URL：`https://api.day.app/xxxxxxxx`，其中 `xxxxxxxx` 就是 BARK_KEY。

自建 Bark Server 用户设置 `BARK_SERVER` 为你自己的地址。

### 企业微信群机器人

1. 创建内部群（至少 3 人），建议命名为「Claude Code 通知」
2. 群聊 → 右上角「⋯」→ 添加群机器人 / 消息推送 → 新创建
3. 复制 Webhook 地址，即 `QYWX_WEBHOOK` 的值

> 找不到入口？管理员需在 [管理后台](https://work.weixin.qq.com/wework_admin/frame) →「应用管理 → 自建 → 消息推送」中启用并添加白名单。

⚠️ Webhook 地址等同于发送权限，不要泄露到公开场所。

## 常见问题

**macOS 收不到系统通知？**
- 检查「系统设置 → 通知 → 脚本编辑器」是否允许通知
- 手动测试：`osascript -e 'display notification "test" with title "test"'`

**收不到 Bark 通知？**
- 确认 `BARK_KEY`：`echo $BARK_KEY`
- 手动测试：`curl "https://api.day.app/$BARK_KEY/测试/Hello"`
- Mac 上 Bark 需开启通知权限

**企业微信收不到？**
- 确认 webhook URL 完整（含 `?key=` 部分）
- 手动测试：`curl "$QYWX_WEBHOOK" -H 'Content-Type: application/json' -d '{"msgtype":"text","text":{"content":"测试"}}'`

**通知太频繁？**
- 调大 `BARK_DELAY`（默认 15s）或 `RATE_LIMIT`（默认 10s）
- 不需要 Stop 通知可删除 settings.json 中对应的 hook

**只用一个推送渠道？**
- 只设置对应环境变量，缺失的渠道自动跳过

**cc-switch 切换 provider 后 hooks 丢失？**
- 重新运行 `bash install.sh`，或手动 `cc-switch config common set`
