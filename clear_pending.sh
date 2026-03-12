#!/usr/bin/env bash
#
# 用户响应时清除所有待推送的通知
# 由 UserPromptSubmit hook 调用
#
# 原理：用户提交了输入 → 说明人在 → 取消所有排队中的推送

STATE_DIR="${HOME}/.claude/hooks/state"

if [ -d "$STATE_DIR" ]; then
    rm -f "${STATE_DIR}"/pending_* 2>/dev/null || true
fi

exit 0
