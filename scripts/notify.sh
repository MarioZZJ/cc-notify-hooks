#!/usr/bin/env bash
#
# Claude Code 分级推送通知 - 主调度器
#
# 机制：
#   读取 JSON 配置 → 解析事件 → 过滤 → 按 delay 排序 → 后台分级推送
#   用户交互 → clear_pending.sh 清除 pending → 推送自动取消
#
# 用法：由 Claude Code hooks 自动调用，通过 stdin 接收 JSON

set -euo pipefail

# ============================================================
#  脚本路径
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHANNELS_DIR="${SCRIPT_DIR}/channels"

# ============================================================
#  配置加载（JSON）
# ============================================================
CONFIG_FILE=""
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "${CLAUDE_PLUGIN_DATA}/notify.json" ]; then
    CONFIG_FILE="${CLAUDE_PLUGIN_DATA}/notify.json"
elif [ -f "${HOME}/.claude/hooks/notify.json" ]; then
    CONFIG_FILE="${HOME}/.claude/hooks/notify.json"
fi

# 平台检测
IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

# 无配置文件时：macOS 用户仍可用系统通知，其他平台直接退出
if [ -z "$CONFIG_FILE" ]; then
    if ! $IS_MACOS; then
        exit 0
    fi
fi

# 读取全局配置
RATE_LIMIT=10
if [ -n "$CONFIG_FILE" ]; then
    RATE_LIMIT=$(jq -r '.rate_limit // 10' "$CONFIG_FILE")
fi

# 状态目录
STATE_DIR="${HOME}/.claude/hooks/state"
mkdir -p "$STATE_DIR"

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
#  创建 pending 标记
# ============================================================
rm -f "${STATE_DIR}"/pending_* 2>/dev/null || true
PENDING_ID="${SESSION_ID}_${NOW}_$$"
PENDING_FILE="${STATE_DIR}/pending_${PENDING_ID}"
echo "$EVENT_TYPE" > "$PENDING_FILE"

# ============================================================
#  构建发送队列并执行
# ============================================================
build_queue() {
    # 无配置文件时，macOS fallback
    if [ -z "$CONFIG_FILE" ]; then
        if $IS_MACOS && [ "$EVENT_TYPE" = "notification" ]; then
            echo "macos 3"
        fi
        return
    fi

    # 遍历所有 channel，输出 "name delay" 行，按 delay 排序
    jq -r '
        .channels // {} | to_entries[] |
        select(.value.enabled == true) |
        "\(.key) \(.value.delay // 15)"
    ' "$CONFIG_FILE" | while read -r ch_name ch_delay; do
        # 检查 channel 脚本存在
        [ -f "${CHANNELS_DIR}/${ch_name}.sh" ] || continue

        # 检查 events 过滤
        local ch_events
        ch_events=$(jq -r ".channels.\"${ch_name}\".events // null" "$CONFIG_FILE")
        if [ "$ch_events" != "null" ]; then
            echo "$ch_events" | jq -e "index(\"${EVENT_TYPE}\")" >/dev/null 2>&1 || continue
        fi

        echo "${ch_name} ${ch_delay}"
    done | sort -k2 -n
}

QUEUE=$(build_queue)

# 无可用 channel 时退出
[ -z "$QUEUE" ] && exit 0

# 后台子 shell 执行 pipeline
(
    elapsed=0

    echo "$QUEUE" | while read -r ch_name ch_delay; do
        # 计算需要等待的时间
        wait_time=$((ch_delay - elapsed))
        if [ "$wait_time" -gt 0 ]; then
            sleep "$wait_time"
            # 等待后检查 pending
            if [ ! -f "$PENDING_FILE" ]; then
                exit 0
            fi
            elapsed=$ch_delay
        fi

        # 加载并调用 channel
        source "${CHANNELS_DIR}/${ch_name}.sh"
        ch_config=$(jq -c ".channels.\"${ch_name}\"" "$CONFIG_FILE" 2>/dev/null || echo "{}")
        "send_${ch_name}" "$TITLE" "$BODY" "$ch_config"
    done

    rm -f "$PENDING_FILE"

) </dev/null >/dev/null 2>&1 &
disown

exit 0
