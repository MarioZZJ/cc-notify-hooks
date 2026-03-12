#!/usr/bin/env bash
#
# Claude Code 分级推送通知脚本
#
# 机制（Linux/远程）：
#   事件触发 → 15s 后推 Bark → 5min 后推企业微信
# 机制（macOS 本地）：
#   事件触发 → 立即弹系统通知 → Bark/企微作为远程备用
#
# 用法：由 Claude Code hooks 自动调用，通过 stdin 接收 JSON

set -euo pipefail

# ============================================================
#  配置区
# ============================================================
BARK_KEY="${BARK_KEY:-}"
BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
QYWX_WEBHOOK="${QYWX_WEBHOOK:-}"

BARK_DELAY="${BARK_DELAY:-15}"
WECHAT_DELAY="${WECHAT_DELAY:-300}"
RATE_LIMIT=10

# 状态目录
STATE_DIR="${HOME}/.claude/hooks/state"
mkdir -p "$STATE_DIR"

# 平台检测
IS_MACOS=false
if [[ "$(uname -s)" == "Darwin" ]]; then
    IS_MACOS=true
fi

# ============================================================
#  读取 hook 事件数据（通过 stdin 接收 JSON）
# ============================================================
EVENT_DATA=$(cat)
EVENT_TYPE="${1:-unknown}"

# 调试日志（放 /tmp 避免污染 hooks 目录）
DEBUG_LOG="/tmp/claude-hooks-debug.log"
echo "[$(date)] EVENT_TYPE=$EVENT_TYPE" >> "$DEBUG_LOG"
echo "$EVENT_DATA" >> "$DEBUG_LOG"
echo "---" >> "$DEBUG_LOG"

# 依赖检查：jq 必须存在
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed" >&2
    exit 0
fi

# 从 JSON 提取关键字段
HOOK_EVENT=$(echo "$EVENT_DATA" | jq -r '.hook_event_name // empty' 2>/dev/null || echo "")
MESSAGE=$(echo "$EVENT_DATA" | jq -r '.message // empty' 2>/dev/null || echo "")
CWD=$(echo "$EVENT_DATA" | jq -r '.cwd // empty' 2>/dev/null || echo "")
PROJECT=$(basename "${CWD:-unknown}")
SESSION_ID=$(echo "$EVENT_DATA" | jq -r '.session_id // empty' 2>/dev/null || echo "unknown")
PERM_MODE=$(echo "$EVENT_DATA" | jq -r '.permission_mode // empty' 2>/dev/null || echo "")
AGENT_ID=$(echo "$EVENT_DATA" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
NOTIF_TYPE=$(echo "$EVENT_DATA" | jq -r '.notification_type // empty' 2>/dev/null || echo "")

# ============================================================
#  子智能体过滤
# ============================================================
if [ -n "$AGENT_ID" ]; then
    exit 0
fi

# ============================================================
#  Stop 事件过滤：防止 Stop Hook 循环
# ============================================================
STOP_ACTIVE=$(echo "$EVENT_DATA" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$EVENT_TYPE" = "stop" ] && [ "$STOP_ACTIVE" = "true" ]; then
    exit 0
fi

# ============================================================
#  防重复：同类事件在 RATE_LIMIT 秒内只推一次
# ============================================================
RATE_FILE="${STATE_DIR}/last_${EVENT_TYPE}"
NOW=$(date +%s)
if [ -f "$RATE_FILE" ]; then
    LAST=$(cat "$RATE_FILE" 2>/dev/null || echo "0")
    if [ $((NOW - LAST)) -lt "$RATE_LIMIT" ]; then
        exit 0
    fi
fi
echo "$NOW" > "$RATE_FILE"

# ============================================================
#  构造通知内容
# ============================================================
case "$EVENT_TYPE" in
    notification)
        case "$NOTIF_TYPE" in
            idle_prompt)
                TITLE="💤 等待响应"
                BODY="${MESSAGE:-Claude 在等你}"
                ;;
            *)
                TITLE="👋 需要你的注意"
                BODY="${MESSAGE:-Claude 需要你的操作}"
                ;;
        esac
        ;;
    stop)
        TITLE="✅ 任务完成"
        BODY="${MESSAGE:-Claude 已完成工作}"
        ;;
    *)
        TITLE="🔔 Claude Code"
        BODY="${MESSAGE:-有新事件}"
        ;;
esac

# 组装前缀
PREFIX="[$PROJECT]"
if [ -n "$PERM_MODE" ]; then
    PREFIX="[$PROJECT|$PERM_MODE]"
fi
BODY="$PREFIX $BODY"

# ============================================================
#  macOS 本地：立即弹系统通知
# ============================================================
if $IS_MACOS; then
    osascript -e "display notification \"$BODY\" with title \"$TITLE\" sound name \"Glass\"" 2>/dev/null || true
fi

# ============================================================
#  创建 pending 标记（用于远程推送的取消机制）
#  先清掉旧的 pending：新事件进来说明之前的事件已被响应
# ============================================================
rm -f "${STATE_DIR}"/pending_* 2>/dev/null || true
PENDING_ID="${SESSION_ID}_${NOW}_$$"
PENDING_FILE="${STATE_DIR}/pending_${PENDING_ID}"
echo "$EVENT_TYPE" > "$PENDING_FILE"

# ============================================================
#  后台分级推送（Bark + 企业微信，不阻塞 Claude Code）
#  macOS 本地已弹过系统通知，这里作为远程备用
# ============================================================
(
    # ---------- 第一级：Bark ----------
    sleep "$BARK_DELAY"

    if [ ! -f "$PENDING_FILE" ]; then
        exit 0
    fi

    if [ -n "$BARK_KEY" ]; then
        curl -sf --max-time 10 \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg key "$BARK_KEY" \
                --arg title "$TITLE" \
                --arg body "$BODY" \
                '{
                    device_key: $key,
                    title: $title,
                    body: $body,
                    level: "timeSensitive",
                    group: "claude-code"
                }')" \
            "${BARK_SERVER}/push" \
            >/dev/null 2>&1 || true
    fi

    # ---------- 第二级：企业微信 ----------
    REMAINING=$((WECHAT_DELAY - BARK_DELAY))
    sleep "$REMAINING"

    if [ ! -f "$PENDING_FILE" ]; then
        exit 0
    fi

    if [ -n "$QYWX_WEBHOOK" ]; then
        curl -sf --max-time 10 \
            "$QYWX_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "$(jq -n --arg content "${TITLE}\n${BODY}" \
                '{"msgtype":"text","text":{"content":$content}}')" \
            >/dev/null 2>&1 || true
    fi

    # 清理标记
    rm -f "$PENDING_FILE"

) </dev/null >/dev/null 2>&1 &
disown

exit 0
