#!/usr/bin/env bash
# cmux 原生通知（OSC 777 协议）
# 本地和 cmux ssh 远程均可用 — 远程通知自动透传到本地 cmux 侧边栏

send_cmux() {
    local title="$1" body="$2" config="$3"

    # 优先用 cmux CLI（本地）
    if command -v cmux &>/dev/null; then
        cmux notify --title "$title" --body "$body" 2>/dev/null && return 0
    fi

    # 回退到 OSC 777（远程 SSH 透传 / 无 CLI 场景）
    printf '\e]777;notify;%s;%s\a' "$title" "$body"
}
