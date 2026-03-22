# cc-notify-hooks

Claude Code 的分级推送通知系统。离开键盘后，按 **macOS 系统通知 → Bark → 企业微信** 逐级提醒，回来操作即自动取消排队中的推送。

## 特性

- **分级延迟推送** — 本地 3s、Bark 15s、企微 5min，逐级升级，避免信息轰炸
- **智能取消** — 用户发消息或点击权限按钮，立即取消所有待推送通知
- **macOS 零配置** — 系统原生通知开箱即用，无需任何外部服务
- **多渠道支持** — Bark（iOS/macOS/Android）+ 企业微信群机器人，按需启用
- **防重复 / 防误发** — 子智能体过滤、rate limiting、`/exit` 后静默、Stop 循环保护
- **配置三层覆盖** — 环境变量 > 配置文件 > 默认值，灵活适配不同环境
- **一键安装** — 交互式脚本，自动合并到 `settings.json`，带备份

## 工作原理

```
Claude Code 事件
    │
    ▼
notify.sh ── 清除旧 pending → 创建新 pending
    │
    ├─ [macOS] 3s 后 → 系统原生通知（仅 Notification 事件）
    │
    ├─ 15s 后 → pending 还在？ ─── 是 → Bark 推送
    │                           └── 否 → 跳过（用户已响应）
    │
    └─ 5min 后 → pending 还在？ ─── 是 → 企业微信推送
                                └── 否 → 跳过

用户交互（发消息 / 点权限按钮）
    │
    └─→ clear_pending.sh → 清除所有 pending → 后续推送全部取消
```

**核心思路**：推送前检查 pending 文件是否还存在。用户一旦回来操作，pending 就被清除，排队中的推送自动作废。

## 监听事件

| Hook | 触发时机 | 行为 |
|------|---------|------|
| Notification | 权限确认、等待输入等 | 分级推送 "需要你的注意" |
| Stop | Claude 回复结束 | 分级推送 "任务完成" |
| UserPromptSubmit | 用户发消息 | 清除所有 pending |
| PreToolUse | 用户点权限按钮 | 清除所有 pending |

通知正文格式：`[项目名|权限模式] 事件描述`

## 安装

### 依赖

| 依赖 | 用途 | macOS | Debian/Ubuntu | RHEL/CentOS |
|------|------|-------|---------------|-------------|
| jq | 解析 JSON | `brew install jq` | `apt install jq` | `yum install jq` |
| curl | 发送推送 | 系统自带 | `apt install curl` | `yum install curl` |

### 运行安装脚本

```bash
git clone https://github.com/MarioZZJ/cc-notify-hooks.git
cd cc-notify-hooks
bash install.sh
```

安装脚本会：

1. 检查依赖
2. 交互式配置推送参数（直接回车使用默认值）
3. 复制脚本到 `~/.claude/hooks/`
4. 将 hooks 合并到 `~/.claude/settings.json`（自动备份原配置）

安装后**重启 Claude Code** 使 hooks 生效。

### 验证

```bash
bash test_notify.sh all     # 测试 Bark + 企业微信连通性
bash test_notify.sh bark    # 仅测试 Bark
bash test_notify.sh wechat  # 仅测试企业微信
bash test_notify.sh hook    # 模拟完整 hook 流程（含延迟）
```

## 配置

### 推送渠道

macOS 本地通知**零配置**。远程推送需要至少配置一个渠道：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `BARK_KEY` | Bark 设备 Key | （空，不启用） |
| `BARK_SERVER` | Bark 服务器地址 | `https://api.day.app` |
| `QYWX_WEBHOOK` | 企业微信 Webhook URL | （空，不启用） |

### 延迟与限流

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `MACOS_DELAY` | macOS 通知延迟（秒） | `3` |
| `BARK_DELAY` | Bark 推送延迟（秒） | `15` |
| `WECHAT_DELAY` | 企业微信推送延迟（秒） | `300` |
| `RATE_LIMIT` | 同类事件防重复窗口（秒） | `10` |

### 配置方式

三种方式，优先级递减：

**1. 环境变量**（推荐，在 `~/.zshrc` 或 `~/.bashrc` 中设置）

```bash
export BARK_KEY="你的-bark-key"
export QYWX_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的key"
```

**2. 配置文件**（由 `install.sh` 生成）

```bash
# ~/.claude/hooks/notify.conf
BARK_KEY="你的-bark-key"
BARK_SERVER="https://api.day.app"
QYWX_WEBHOOK=""
BARK_DELAY=15
WECHAT_DELAY=300
```

**3. 默认值**（硬编码在脚本中）

缺失的渠道自动跳过，不会报错。只用一个渠道完全没问题。

## 获取推送凭证

### Bark

1. 安装 [Bark App](https://github.com/Finb/Bark)（iOS / macOS / Android）
2. 打开 App，首页显示推送 URL：`https://api.day.app/xxxxxxxx`
3. `xxxxxxxx` 部分即为 `BARK_KEY`

自建 Bark Server 用户设置 `BARK_SERVER` 为你自己的地址。

### 企业微信群机器人

1. 创建企业微信内部群（至少 3 人）
2. 群聊 → 右上角「⋯」→ 群机器人 → 添加 → 新创建
3. 复制 Webhook 地址，即为 `QYWX_WEBHOOK`

> 找不到入口？需管理员在[管理后台](https://work.weixin.qq.com/wework_admin/frame) → 应用管理 → 群机器人中启用。

**注意**：Webhook URL 等同于发送权限，不要泄露到公开场所。

## 过滤规则

脚本内置了多层过滤，避免无意义的推送：

| 规则 | 说明 |
|------|------|
| 子智能体过滤 | `agent_id` 非空时跳过，避免子任务级联通知 |
| Stop 循环保护 | `stop_hook_active=true` 时跳过 |
| `/exit` 静默 | 用户输入 `/exit` 后标记，后续 Stop 事件不推送 |
| Rate Limiting | 同类事件 10 秒内只推一次 |

## 文件结构

```
cc-notify-hooks/
├── notify.sh          # 核心推送脚本（分级延迟 + pending 检查）
├── clear_pending.sh   # 用户交互时清除待推送
├── install.sh         # 交互式安装脚本
├── test_notify.sh     # 连通性测试
├── settings.json      # Claude Code hooks 配置模板
└── README.md

安装后：
~/.claude/
├── settings.json            # hooks 已合并
└── hooks/
    ├── notify.sh
    ├── clear_pending.sh
    ├── notify.conf          # 推送参数配置
    └── state/
        ├── pending_*        # 待推送标记
        └── last_*           # 防重复时间戳
```

调试日志：`/tmp/claude-hooks-debug.log`

## 常见问题

<details>
<summary><b>macOS 收不到系统通知</b></summary>

检查「系统设置 → 通知 → 脚本编辑器」是否允许通知。手动验证：

```bash
osascript -e 'display notification "test" with title "test"'
```
</details>

<details>
<summary><b>Bark 推送不到</b></summary>

1. 确认 Key：`echo $BARK_KEY`
2. 手动测试：`curl "https://api.day.app/$BARK_KEY/测试/Hello"`
3. 检查网络（Bark 服务器在境外，可能需要代理）
</details>

<details>
<summary><b>企业微信收不到</b></summary>

1. 确认 URL 完整（含 `?key=` 部分）
2. 手动测试：
   ```bash
   curl "$QYWX_WEBHOOK" \
     -H 'Content-Type: application/json' \
     -d '{"msgtype":"text","text":{"content":"测试"}}'
   ```
</details>

<details>
<summary><b>通知太频繁</b></summary>

调大延迟参数：

```bash
# ~/.claude/hooks/notify.conf
BARK_DELAY=30
WECHAT_DELAY=600
RATE_LIMIT=30
```

不需要某个事件的通知，可编辑 `~/.claude/settings.json` 删除对应 hook。
</details>

<details>
<summary><b>只想用其中一个渠道</b></summary>

只配置对应参数即可，未配置的渠道自动跳过。
</details>

## 卸载

```bash
# 删除脚本和配置
rm -rf ~/.claude/hooks/notify.sh ~/.claude/hooks/clear_pending.sh ~/.claude/hooks/notify.conf ~/.claude/hooks/state

# 从 settings.json 中移除 hooks（或手动编辑）
# 需要手动删除 settings.json 中的 Notification/Stop/UserPromptSubmit/PreToolUse 相关条目
```

## License

MIT
