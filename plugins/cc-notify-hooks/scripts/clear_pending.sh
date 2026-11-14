#!/usr/bin/env bash
#
# 清除当前 session 排队中的通知。
# 无参数清除当前 session 全部 pending；可传入 event kind 和调用 id 定向清理。

STATE_BASE="${PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/hooks}}"
STATE_DIR="${CC_NOTIFY_STATE_DIR:-${STATE_BASE}/state}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

EVENT_DATA=$(cat 2>/dev/null || true)
[ -n "$EVENT_DATA" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$EVENT_DATA" | jq -e 'type == "object"' >/dev/null 2>&1 || exit 0

safe_state_key() {
    local value="${1:-unknown}"
    value=$(printf '%s' "$value" | LC_ALL=C tr -c '[:alnum:]_.-' '_' | cut -c1-96)
    printf '%s' "${value:-unknown}"
}

HOOK_EVENT=$(printf '%s' "$EVENT_DATA" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$EVENT_DATA" | jq -r '.session_id // empty' 2>/dev/null || true)
TURN_ID=$(printf '%s' "$EVENT_DATA" | jq -r '.turn_id // empty' 2>/dev/null || true)
SESSION_KEY=$(safe_state_key "${SESSION_ID:-${TURN_ID:-unknown}}")
CLEAR_KIND="${1:-}"

if [ "$HOOK_EVENT" = "UserPromptSubmit" ]; then
    MESSAGE=$(printf '%s' "$EVENT_DATA" | jq -r '.message // .prompt // empty' 2>/dev/null || true)
    if [[ "$MESSAGE" =~ ^[[:space:]]*/exit[[:space:]]*$ ]]; then
        touch "${STATE_DIR}/exiting_${SESSION_KEY}"
    else
        rm -f "${STATE_DIR}/exiting_${SESSION_KEY}" 2>/dev/null || true
    fi
fi

if [ -n "$CLEAR_KIND" ]; then
    KIND_KEY=$(safe_state_key "$CLEAR_KIND")
    if [ -n "${2:-}" ]; then
        TOOL_USE_KEY=$(safe_state_key "$2")
        rm -f "${STATE_DIR}/pending_${SESSION_KEY}_${KIND_KEY}_${TOOL_USE_KEY}_"* 2>/dev/null || true
    else
        rm -f "${STATE_DIR}/pending_${SESSION_KEY}_${KIND_KEY}_"* 2>/dev/null || true
    fi
else
    rm -f "${STATE_DIR}/pending_${SESSION_KEY}_"* 2>/dev/null || true
fi

exit 0
