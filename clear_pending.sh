#!/usr/bin/env bash
#
# 用户交互时清除所有待推送的通知
# 由 UserPromptSubmit / PreToolUse hook 调用
#
# 原理：
#   UserPromptSubmit → 用户发了消息 → 取消推送
#   PreToolUse → 用户点了权限按钮 → 取消推送
#   /exit → 设置退出标记，后续 Stop 事件跳过

STATE_DIR="${HOME}/.claude/hooks/state"
[ -d "$STATE_DIR" ] || exit 0

# 读取事件数据
EVENT_DATA=$(cat 2>/dev/null || echo "")

# 仅 UserPromptSubmit 事件检测 /exit
if command -v jq &>/dev/null && [ -n "$EVENT_DATA" ]; then
    HOOK_EVENT=$(echo "$EVENT_DATA" | jq -r '.hook_event_name // empty' 2>/dev/null || echo "")
    if [ "$HOOK_EVENT" = "UserPromptSubmit" ]; then
        MESSAGE=$(echo "$EVENT_DATA" | jq -r '.message // empty' 2>/dev/null || echo "")
        if [[ "$MESSAGE" =~ ^[[:space:]]*/exit[[:space:]]*$ ]]; then
            touch "${STATE_DIR}/exiting"
        else
            rm -f "${STATE_DIR}/exiting" 2>/dev/null || true
        fi
    fi
fi

# 清除所有 pending 通知
rm -f "${STATE_DIR}"/pending_* 2>/dev/null || true

exit 0
