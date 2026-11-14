#!/usr/bin/env bash
#
# cc-notify-hooks 分级推送通知 - 主调度器
#
# 机制：
#   读取 JSON 配置 → 解析事件 → 过滤 → 按 delay 排序 → 后台分级推送
#   用户交互 → clear_pending.sh 清除 pending → 推送自动取消
#
# 用法：由 hooks 自动调用，通过 stdin 接收 JSON

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
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
REASONIX_HOME_DIR="${REASONIX_HOME:-${HOME}/.reasonix}"
DSH_HOME_DIR="${DSH_HOME:-${HOME}/.dsh}"
if [ -n "${CC_NOTIFY_CONFIG:-}" ] && [ -f "${CC_NOTIFY_CONFIG}" ]; then
    CONFIG_FILE="${CC_NOTIFY_CONFIG}"
elif [ -n "${PLUGIN_DATA:-}" ] && [ -f "${PLUGIN_DATA}/notify.json" ]; then
    CONFIG_FILE="${PLUGIN_DATA}/notify.json"
elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "${CLAUDE_PLUGIN_DATA}/notify.json" ]; then
    CONFIG_FILE="${CLAUDE_PLUGIN_DATA}/notify.json"
elif [ -f "${HOME}/.config/cc-notify-hooks/notify.json" ]; then
    CONFIG_FILE="${HOME}/.config/cc-notify-hooks/notify.json"
elif [ -f "${CODEX_HOME_DIR}/cc-notify-hooks/notify.json" ]; then
    CONFIG_FILE="${CODEX_HOME_DIR}/cc-notify-hooks/notify.json"
elif [ -f "${REASONIX_HOME_DIR}/cc-notify-hooks/notify.json" ]; then
    CONFIG_FILE="${REASONIX_HOME_DIR}/cc-notify-hooks/notify.json"
elif [ -f "${DSH_HOME_DIR}/cc-notify-hooks/notify.json" ]; then
    CONFIG_FILE="${DSH_HOME_DIR}/cc-notify-hooks/notify.json"
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

# 缺少 jq 时安静降级，不能让通知 hook 阻塞 Codex。
command -v jq >/dev/null 2>&1 || exit 0

# 读取全局配置
RATE_LIMIT=10
if [ -n "$CONFIG_FILE" ]; then
    RATE_LIMIT=$(jq -r '.rate_limit // 10' "$CONFIG_FILE")
fi
[[ "$RATE_LIMIT" =~ ^[0-9]+$ ]] || RATE_LIMIT=10

# 状态目录
STATE_BASE="${PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/hooks}}"
STATE_DIR="${CC_NOTIFY_STATE_DIR:-${STATE_BASE}/state}"
if [ "${CC_NOTIFY_RENDER_ONLY:-}" != "1" ]; then
    mkdir -p "$STATE_DIR"
fi

# ============================================================
#  读取 hook 事件数据
# ============================================================
EVENT_DATA=$(cat)
EVENT_TYPE="${1:-unknown}"
EVENT_KIND="${2:-$EVENT_TYPE}"

# 调试日志
DEBUG_LOG="/tmp/claude-hooks-debug.log"
if [ "${CC_NOTIFY_RENDER_ONLY:-}" != "1" ]; then
    {
        echo "[$(date)] EVENT_TYPE=$EVENT_TYPE"
        echo "$EVENT_DATA"
        echo "---"
    } >> "$DEBUG_LOG"
fi

# 提取字段
# hook_event_name（Claude/Codex/插件导入格式）优先，event（Reasonix 原生格式）兜底
HOOK_EVENT=$(printf '%s' "$EVENT_DATA" | jq -r '.hook_event_name // .event // empty' 2>/dev/null || echo "")
MESSAGE=$(printf '%s' "$EVENT_DATA" | jq -r '.message // .prompt // .error_description // .error // empty | if type == "string" then . else tostring end' 2>/dev/null || echo "")
CWD=$(printf '%s' "$EVENT_DATA" | jq -r '.cwd // empty' 2>/dev/null || echo "")
PROJECT=$(basename "${CWD:-unknown}")
[ -n "$PROJECT" ] || PROJECT="unknown"
SESSION_ID=$(printf '%s' "$EVENT_DATA" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || echo "")
TURN_ID=$(printf '%s' "$EVENT_DATA" | jq -r '.turn_id // empty' 2>/dev/null || echo "")
TOOL_USE_ID=$(printf '%s' "$EVENT_DATA" | jq -r '.tool_use_id // empty' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(printf '%s' "$EVENT_DATA" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
PERM_MODE=$(printf '%s' "$EVENT_DATA" | jq -r '.permission_mode // empty' 2>/dev/null || echo "")
AGENT_ID=$(printf '%s' "$EVENT_DATA" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
NOTIF_TYPE=$(printf '%s' "$EVENT_DATA" | jq -r '.notification_type // empty' 2>/dev/null || echo "")
MODEL=$(printf '%s' "$EVENT_DATA" | jq -r '.model // empty' 2>/dev/null || echo "")
TOOL_NAME=$(printf '%s' "$EVENT_DATA" | jq -r '(.tool_name // .tool.name // .tool // empty) | if type == "string" then . else empty end' 2>/dev/null || echo "")
LAST_ASSISTANT_MESSAGE=$(printf '%s' "$EVENT_DATA" | jq -r '.last_assistant_message // .lastAssistantText // empty' 2>/dev/null || echo "")
QUESTION_COUNT=$(printf '%s' "$EVENT_DATA" | jq -r '
    if (.tool_input.questions? | type) == "array"
    then (.tool_input.questions | length)
    else 0
    end
' 2>/dev/null || echo "0")
QUESTION_HEADER=$(printf '%s' "$EVENT_DATA" | jq -r '.tool_input.questions[0].header // empty' 2>/dev/null || echo "")
QUESTION_TEXT=$(printf '%s' "$EVENT_DATA" | jq -r '.tool_input.questions[0].question // empty' 2>/dev/null || echo "")
OPTION_LABELS=$(printf '%s' "$EVENT_DATA" | jq -c '
    [(.tool_input.questions[0].options // [])[]?
        | .label?
        | select(type == "string" and length > 0)]
' 2>/dev/null || echo '[]')
[[ "$QUESTION_COUNT" =~ ^[0-9]+$ ]] || QUESTION_COUNT=0

safe_state_key() {
    local value="${1:-unknown}"
    value=$(printf '%s' "$value" | LC_ALL=C tr -c '[:alnum:]_.-' '_' | cut -c1-96)
    printf '%s' "${value:-unknown}"
}

SESSION_SCOPE="${SESSION_ID:-${TURN_ID:-unknown}}"
SESSION_KEY=$(safe_state_key "$SESSION_SCOPE")
EVENT_KIND_KEY=$(safe_state_key "$EVENT_KIND")
TOOL_USE_KEY=$(safe_state_key "${TOOL_USE_ID:-no-call}")

NOW=$(date +%s)

if [ "${CC_NOTIFY_RENDER_ONLY:-}" != "1" ]; then
    # ============================================================
    #  过滤规则
    # ============================================================

    # 子智能体：跳过
    [ -n "$AGENT_ID" ] && exit 0

    # Stop hook 循环保护
    STOP_ACTIVE=$(printf '%s' "$EVENT_DATA" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
    if [ "$EVENT_TYPE" = "stop" ] && [ "$STOP_ACTIVE" = "true" ]; then
        exit 0
    fi

    # /exit 后的 Stop 事件：跳过
    if [ "$EVENT_TYPE" = "stop" ] && [ -f "${STATE_DIR}/exiting_${SESSION_KEY}" ]; then
        rm -f "${STATE_DIR}/exiting_${SESSION_KEY}"
        exit 0
    fi

    # 防重复：状态按 session + event kind 隔离。
    # request_user_input 用 tool_use_id 精确去重，不吞掉紧接着出现的新问题。
    RATE_FILE="${STATE_DIR}/last_${SESSION_KEY}_${EVENT_KIND_KEY}"
    if [ -f "$RATE_FILE" ]; then
        LAST=0
        LAST_TOOL_USE_KEY=""
        IFS=$'\t' read -r LAST LAST_TOOL_USE_KEY < "$RATE_FILE" || true
        [[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0

        if { [ "$EVENT_KIND" = "user_input" ] || [ "$EVENT_KIND" = "permission" ]; } && [ -n "$TOOL_USE_ID" ]; then
            [ "$LAST_TOOL_USE_KEY" = "$TOOL_USE_KEY" ] && exit 0
        elif [ $((NOW - LAST)) -lt "$RATE_LIMIT" ]; then
            exit 0
        fi
    fi
    printf '%s\t%s\n' "$NOW" "$TOOL_USE_KEY" > "$RATE_FILE"
fi

# ============================================================
#  构造通知内容
# ============================================================
if [ -n "${CC_NOTIFY_AGENT:-}" ]; then
    case "$CC_NOTIFY_AGENT" in
        claude) AGENT_NAME="Claude Code" ;;
        codex) AGENT_NAME="Codex" ;;
        dsh) AGENT_NAME="dsh" ;;
        magpie) AGENT_NAME="Magpie" ;;
        *) AGENT_NAME="$CC_NOTIFY_AGENT" ;;
    esac
elif [ -n "${REASONIX_PLUGIN_ROOT:-}" ]; then
    AGENT_NAME="Reasonix"
elif [ -n "${DSH_CC_NOTIFY:-}" ]; then
    AGENT_NAME="dsh"
elif [ "$HOOK_EVENT" = "Notification" ]; then
    AGENT_NAME="Claude Code"
elif [[ "${TRANSCRIPT_PATH:-}" == *".claude"* ]]; then
    AGENT_NAME="Claude Code"
else
    AGENT_NAME="Codex"
fi

first_line() {
    printf '%s' "$1" | awk 'NF {print; exit}'
}

trim_text() {
    printf '%s' "$1" | awk '{$1=$1; print}'
}

truncate_text() {
    local text="$1" max_len="${2:-120}"
    if [ "${#text}" -le "$max_len" ]; then
        printf '%s' "$text"
    else
        printf '%s...' "${text:0:$((max_len - 3))}"
    fi
}

short_session_id() {
    local session="$1"
    [ -n "$session" ] || return 0
    printf '%s' "${session:0:8}"
}

HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "")
EVENT_NAME="${HOOK_EVENT:-$EVENT_TYPE}"
SUMMARY_SOURCE=""
STATUS_LABEL="需要确认 🔔"
STATUS_COLOR="orange"

if [ "$EVENT_KIND" = "gateway_response" ]; then
    STATUS_LABEL="模型响应完成 💬"
    STATUS_COLOR="blue"
    SUMMARY_SOURCE="${MESSAGE:-模型已返回响应}"
elif [ "$EVENT_KIND" = "error" ] || [ "$EVENT_KIND" = "gateway_error" ]; then
    STATUS_LABEL="任务异常 ⚠️"
    [ "$EVENT_KIND" = "gateway_error" ] && STATUS_LABEL="模型请求异常 ⚠️"
    STATUS_COLOR="red"
    SUMMARY_SOURCE="${MESSAGE:-任务因错误停止}"
elif [ "$EVENT_KIND" = "user_input" ]; then
    STATUS_LABEL="需要回复 🔔"
    STATUS_COLOR="orange"
    SUMMARY_SOURCE="${QUESTION_HEADER:-${QUESTION_TEXT:-${AGENT_NAME} 正在等待你的输入}}"
else
    case "$EVENT_TYPE" in
        notification)
            case "$NOTIF_TYPE" in
                idle_prompt)
                    STATUS_LABEL="等待响应 ⏳"
                    STATUS_COLOR="blue"
                    SUMMARY_SOURCE="${MESSAGE:-等待你的响应}"
                    ;;
                *)
                    STATUS_LABEL="需要确认 🔔"
                    STATUS_COLOR="orange"
                    SUMMARY_SOURCE="${MESSAGE:-需要你的操作}"
                    ;;
            esac
            ;;
        stop)
            STATUS_LABEL="任务完成 ✅"
            STATUS_COLOR="green"
            SUMMARY_SOURCE=$(first_line "$LAST_ASSISTANT_MESSAGE")
            SUMMARY_SOURCE="${SUMMARY_SOURCE:-任务已完成}"
            ;;
        *)
            STATUS_LABEL="异常 ⚠️"
            STATUS_COLOR="red"
            SUMMARY_SOURCE="${MESSAGE:-${HOOK_EVENT:-有新事件}}"
            ;;
    esac
fi

SUMMARY_SHORT=$(truncate_text "$(trim_text "$(first_line "$SUMMARY_SOURCE")")" 120)
[ -n "$SUMMARY_SHORT" ] || SUMMARY_SHORT="${EVENT_NAME:-有新事件}"
SESSION_SHORT=$(short_session_id "$SESSION_SCOPE")

TITLE="${AGENT_NAME} · ${STATUS_LABEL}"
if [ "$EVENT_KIND" = "user_input" ]; then
    BODY="[$PROJECT] $SUMMARY_SHORT · ${QUESTION_COUNT} 个问题 · Session ${SESSION_SHORT:-unknown}"
else
    BODY="[$PROJECT] $SUMMARY_SHORT"
    [ -n "$TOOL_NAME" ] && BODY="${BODY} · ${TOOL_NAME}"
fi

EVENT_JSON=$(
    jq -n \
        --arg title "$TITLE" \
        --arg body "$BODY" \
        --arg agent "$AGENT_NAME" \
        --arg project "$PROJECT" \
        --arg status_label "$STATUS_LABEL" \
        --arg status_color "$STATUS_COLOR" \
        --arg summary_short "$SUMMARY_SHORT" \
        --arg event_name "$EVENT_NAME" \
        --arg event_kind "$EVENT_KIND" \
        --arg tool_name "$TOOL_NAME" \
        --arg model "$MODEL" \
        --arg cwd "$CWD" \
        --arg hostname "$HOSTNAME_SHORT" \
        --arg session_id "$SESSION_ID" \
        --arg session_short "$SESSION_SHORT" \
        --argjson question_count "$QUESTION_COUNT" \
        --argjson option_labels "$OPTION_LABELS" \
        '{
            schema_version: 1,
            title: $title,
            body: $body,
            agent: $agent,
            project: $project,
            status_label: $status_label,
            status_color: $status_color,
            summary_short: $summary_short,
            event_name: $event_name,
            event_kind: $event_kind,
            tool_name: $tool_name,
            model: $model,
            cwd: $cwd,
            hostname: $hostname,
            session_id: $session_id,
            session_short: $session_short,
            question_count: $question_count,
            option_labels: $option_labels
        }'
)

if [ "${CC_NOTIFY_RENDER_ONLY:-}" = "1" ]; then
    printf '%s\n' "$EVENT_JSON"
    exit 0
fi

# ============================================================
#  创建 pending 标记
# ============================================================
if [ "${CC_NOTIFY_AGENT:-}" = "dsh" ] &&
   { [ "$EVENT_KIND" = "permission" ] || [ "$EVENT_KIND" = "user_input" ]; }; then
    # dsh 可以同时等待多个审批，保留其他请求的通知。
    rm -f "${STATE_DIR}/pending_${SESSION_KEY}_${EVENT_KIND_KEY}_${TOOL_USE_KEY}_"* 2>/dev/null || true
else
    rm -f "${STATE_DIR}/pending_${SESSION_KEY}_"* 2>/dev/null || true
fi
PENDING_FILE="${STATE_DIR}/pending_${SESSION_KEY}_${EVENT_KIND_KEY}_${TOOL_USE_KEY}_${NOW}_$$"
echo "$EVENT_KIND" > "$PENDING_FILE"

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
            elapsed=$ch_delay
        fi

        # 延迟为 0 或多个渠道延迟相同时，也在每次发送前检查取消状态。
        if [ ! -f "$PENDING_FILE" ]; then
            exit 0
        fi

        # 加载并调用 channel
        source "${CHANNELS_DIR}/${ch_name}.sh"
        ch_config=$(jq -c ".channels.\"${ch_name}\"" "$CONFIG_FILE" 2>/dev/null || echo "{}")
        "send_${ch_name}" "$TITLE" "$BODY" "$ch_config" "$EVENT_JSON" || true
    done

    rm -f "$PENDING_FILE"

) </dev/null >/dev/null 2>&1 &
disown

exit 0
