#!/usr/bin/env bash
#
# Claude Code 分级推送通知脚本
#
# 机制：
#   Notification 事件 → macOS 3s 延迟弹系统通知 → 15s Bark → 5min 企微
#   Stop 事件 → 不弹本地通知（用户能看到终端）→ 15s Bark → 5min 企微
#   用户交互（输入/点击）→ 取消所有排队中的推送
#
# 用法：由 Claude Code hooks 自动调用，通过 stdin 接收 JSON

set -euo pipefail

# ============================================================
#  配置区（配置文件 > 环境变量 > 默认值）
# ============================================================
_CONF="${HOME}/.claude/hooks/notify.conf"
# 先保存环境变量
_ENV_BARK_KEY="${BARK_KEY:-}"
_ENV_BARK_SERVER="${BARK_SERVER:-}"
_ENV_QYWX_WEBHOOK="${QYWX_WEBHOOK:-}"
_ENV_BARK_DELAY="${BARK_DELAY:-}"
_ENV_WECHAT_DELAY="${WECHAT_DELAY:-}"
_ENV_MACOS_DELAY="${MACOS_DELAY:-}"
_ENV_RATE_LIMIT="${RATE_LIMIT:-}"

# 读取配置文件
if [ -f "$_CONF" ]; then
    # shellcheck source=/dev/null
    source "$_CONF"
fi

# 环境变量覆盖配置文件（非空时）
[ -n "$_ENV_BARK_KEY" ]     && BARK_KEY="$_ENV_BARK_KEY"
[ -n "$_ENV_BARK_SERVER" ]  && BARK_SERVER="$_ENV_BARK_SERVER"
[ -n "$_ENV_QYWX_WEBHOOK" ] && QYWX_WEBHOOK="$_ENV_QYWX_WEBHOOK"
[ -n "$_ENV_BARK_DELAY" ]   && BARK_DELAY="$_ENV_BARK_DELAY"
[ -n "$_ENV_WECHAT_DELAY" ] && WECHAT_DELAY="$_ENV_WECHAT_DELAY"
[ -n "$_ENV_MACOS_DELAY" ]  && MACOS_DELAY="$_ENV_MACOS_DELAY"
[ -n "$_ENV_RATE_LIMIT" ]   && RATE_LIMIT="$_ENV_RATE_LIMIT"

# 最终默认值
BARK_KEY="${BARK_KEY:-}"
BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
QYWX_WEBHOOK="${QYWX_WEBHOOK:-}"
BARK_DELAY="${BARK_DELAY:-15}"
WECHAT_DELAY="${WECHAT_DELAY:-300}"
MACOS_DELAY="${MACOS_DELAY:-3}"
RATE_LIMIT="${RATE_LIMIT:-10}"

# 状态目录
STATE_DIR="${HOME}/.claude/hooks/state"
mkdir -p "$STATE_DIR"

# 平台检测
IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

# ============================================================
#  读取 hook 事件数据
# ============================================================
EVENT_DATA=$(cat)
EVENT_TYPE="${1:-unknown}"

# 调试日志
DEBUG_LOG="/tmp/claude-hooks-debug.log"
{
    echo "[$(date)] EVENT_TYPE=$EVENT_TYPE"
    echo "$EVENT_DATA"
    echo "---"
} >> "$DEBUG_LOG"

# 依赖检查
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required" >&2
    exit 0
fi

# 提取字段
HOOK_EVENT=$(echo "$EVENT_DATA" | jq -r '.hook_event_name // empty' 2>/dev/null || echo "")
MESSAGE=$(echo "$EVENT_DATA" | jq -r '.message // empty' 2>/dev/null || echo "")
CWD=$(echo "$EVENT_DATA" | jq -r '.cwd // empty' 2>/dev/null || echo "")
PROJECT=$(basename "${CWD:-unknown}")
SESSION_ID=$(echo "$EVENT_DATA" | jq -r '.session_id // empty' 2>/dev/null || echo "unknown")
PERM_MODE=$(echo "$EVENT_DATA" | jq -r '.permission_mode // empty' 2>/dev/null || echo "")
AGENT_ID=$(echo "$EVENT_DATA" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
NOTIF_TYPE=$(echo "$EVENT_DATA" | jq -r '.notification_type // empty' 2>/dev/null || echo "")

# ============================================================
#  过滤规则
# ============================================================

# 子智能体：跳过
[ -n "$AGENT_ID" ] && exit 0

# Stop hook 循环保护
STOP_ACTIVE=$(echo "$EVENT_DATA" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$EVENT_TYPE" = "stop" ] && [ "$STOP_ACTIVE" = "true" ]; then
    exit 0
fi

# /exit 后的 Stop 事件：跳过
if [ "$EVENT_TYPE" = "stop" ] && [ -f "${STATE_DIR}/exiting" ]; then
    rm -f "${STATE_DIR}/exiting"
    exit 0
fi

# 防重复：同类事件在 RATE_LIMIT 秒内只推一次
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
                TITLE="等待响应"
                BODY="${MESSAGE:-Claude 在等你}"
                ;;
            *)
                TITLE="需要你的注意"
                BODY="${MESSAGE:-Claude 需要你的操作}"
                ;;
        esac
        ;;
    stop)
        TITLE="任务完成"
        BODY="${MESSAGE:-Claude 已完成工作}"
        ;;
    *)
        TITLE="Claude Code"
        BODY="${MESSAGE:-有新事件}"
        ;;
esac

PREFIX="[$PROJECT]"
[ -n "$PERM_MODE" ] && PREFIX="[$PROJECT|$PERM_MODE]"
BODY="$PREFIX $BODY"

# ============================================================
#  创建 pending 标记（先清旧的）
# ============================================================
rm -f "${STATE_DIR}"/pending_* 2>/dev/null || true
PENDING_ID="${SESSION_ID}_${NOW}_$$"
PENDING_FILE="${STATE_DIR}/pending_${PENDING_ID}"
echo "$EVENT_TYPE" > "$PENDING_FILE"

# ============================================================
#  后台分级推送
#  macOS 系统通知：仅 Notification 事件，延迟 MACOS_DELAY 后发送
#  Bark / 企微：所有事件，延迟 BARK_DELAY / WECHAT_DELAY 后发送
#  发送前都检查 pending，用户交互过则取消
# ============================================================
(
    # ---------- macOS 系统通知（仅 notification 事件）----------
    if $IS_MACOS && [ "$EVENT_TYPE" = "notification" ]; then
        sleep "$MACOS_DELAY"
        if [ -f "$PENDING_FILE" ]; then
            # 转义特殊字符防止 osascript 注入
            SAFE_BODY=$(printf '%s' "$BODY" | sed 's/\\/\\\\/g;s/"/\\"/g')
            SAFE_TITLE=$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g;s/"/\\"/g')
            osascript -e "display notification \"$SAFE_BODY\" with title \"$SAFE_TITLE\" sound name \"Glass\"" 2>/dev/null || true
        fi
        # 扣除已等待时间
        BARK_WAIT=$((BARK_DELAY - MACOS_DELAY))
        [ "$BARK_WAIT" -lt 0 ] && BARK_WAIT=0
    else
        BARK_WAIT="$BARK_DELAY"
    fi

    # ---------- 第一级：Bark ----------
    sleep "$BARK_WAIT"

    if [ ! -f "$PENDING_FILE" ]; then exit 0; fi

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
    [ "$REMAINING" -lt 0 ] && REMAINING=0
    sleep "$REMAINING"

    if [ ! -f "$PENDING_FILE" ]; then exit 0; fi

    if [ -n "$QYWX_WEBHOOK" ]; then
        curl -sf --max-time 10 \
            "$QYWX_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "$(jq -n --arg content "${TITLE}\n${BODY}" \
                '{"msgtype":"text","text":{"content":$content}}')" \
            >/dev/null 2>&1 || true
    fi

    rm -f "$PENDING_FILE"

) </dev/null >/dev/null 2>&1 &
disown

exit 0
