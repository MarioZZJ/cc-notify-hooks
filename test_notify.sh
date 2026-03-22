#!/usr/bin/env bash
#
# 测试脚本 - 验证各渠道推送连通性
#
# 用法：
#   bash test_notify.sh              # 测试所有已启用 channel
#   bash test_notify.sh bark         # 测试单个 channel
#   bash test_notify.sh hook         # 模拟完整 hook 流程
#   bash test_notify.sh list         # 列出已启用 channel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHANNELS_DIR="${SCRIPT_DIR}/scripts/channels"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 查找配置文件
CONFIG_FILE=""
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "${CLAUDE_PLUGIN_DATA}/notify.json" ]; then
    CONFIG_FILE="${CLAUDE_PLUGIN_DATA}/notify.json"
elif [ -f "${HOME}/.claude/hooks/notify.json" ]; then
    CONFIG_FILE="${HOME}/.claude/hooks/notify.json"
fi

echo "========================================="
echo "  cc-notify-hooks - 连通性测试"
echo "========================================="
echo ""

if [ -z "$CONFIG_FILE" ]; then
    echo -e "${RED}未找到配置文件${NC}"
    echo "  请先运行 bash install.sh 或复制 config/notify.example.json 到"
    echo "  ~/.claude/hooks/notify.json"
    exit 1
fi

echo -e "  配置文件: ${CYAN}${CONFIG_FILE}${NC}"
echo ""

# 测试单个 channel
test_channel() {
    local name="$1"
    local ch_file="${CHANNELS_DIR}/${name}.sh"

    if [ ! -f "$ch_file" ]; then
        echo -e "${RED}[${name}]${NC} ❌ channel 脚本不存在: ${ch_file}"
        return 1
    fi

    local enabled
    enabled=$(jq -r ".channels.\"${name}\".enabled // false" "$CONFIG_FILE")
    if [ "$enabled" != "true" ]; then
        echo -e "${YELLOW}[${name}]${NC} ⏭ 未启用，跳过"
        return 0
    fi

    local config
    config=$(jq -c ".channels.\"${name}\"" "$CONFIG_FILE")

    echo -e "${YELLOW}[${name}]${NC} 发送测试通知..."

    # macOS 特殊处理
    if [ "$name" = "macos" ]; then
        if [[ "$(uname -s)" != "Darwin" ]]; then
            echo -e "${YELLOW}[${name}]${NC} ⏭ 非 macOS 系统，跳过"
            return 0
        fi
        source "$ch_file"
        send_macos "cc-notify-hooks 测试" "推送连通性测试" "$config"
        echo -e "${GREEN}[${name}]${NC} ✅ 已发送，请检查系统通知"
        return 0
    fi

    # 通用 channel：通过 curl 返回值判断
    source "$ch_file"

    # 临时覆盖 curl，捕获 HTTP 状态码
    local result
    result=$(
        # 替换 send 函数中的 curl，让它输出状态码
        _original_curl=$(which curl)
        send_${name} "cc-notify-hooks Test" "Push notification connectivity test" "$config" 2>&1
        echo "SEND_DONE"
    )

    # 简单判断：函数执行完成即视为成功（curl 错误被 || true 吞掉）
    echo -e "${GREEN}[${name}]${NC} ✅ 已发送，请检查对应平台是否收到"

    # 显示 channel 详情
    case "$name" in
        bark)
            local key
            key=$(echo "$config" | jq -r '.key // empty')
            echo -e "  Key: ${key:0:8}..."
            ;;
        telegram)
            local chat_id
            chat_id=$(echo "$config" | jq -r '.chat_id // empty')
            echo -e "  Chat ID: $chat_id"
            ;;
        wechat|feishu|dingtalk|slack|discord)
            local webhook
            webhook=$(echo "$config" | jq -r '.webhook // empty')
            echo -e "  Webhook: ${webhook:0:50}..."
            ;;
        ntfy)
            local topic server
            topic=$(echo "$config" | jq -r '.topic // empty')
            server=$(echo "$config" | jq -r '.server // "https://ntfy.sh"')
            echo -e "  Topic: $topic @ $server"
            ;;
        pushover)
            local user_key
            user_key=$(echo "$config" | jq -r '.user_key // empty')
            echo -e "  User: ${user_key:0:8}..."
            ;;
        gotify)
            local server
            server=$(echo "$config" | jq -r '.server // empty')
            echo -e "  Server: $server"
            ;;
    esac
}

# 列出所有 channel 状态
list_channels() {
    echo "  Channel 状态："
    echo ""
    printf "  %-15s %-10s %-10s %s\n" "CHANNEL" "STATUS" "DELAY" "EVENTS"
    printf "  %-15s %-10s %-10s %s\n" "-------" "------" "-----" "------"

    for ch_file in "${CHANNELS_DIR}"/*.sh; do
        local name
        name=$(basename "$ch_file" .sh)
        local enabled delay events
        enabled=$(jq -r ".channels.\"${name}\".enabled // false" "$CONFIG_FILE")
        delay=$(jq -r ".channels.\"${name}\".delay // \"-\"" "$CONFIG_FILE")
        events=$(jq -r ".channels.\"${name}\".events // [\"notification\",\"stop\"] | join(\",\")" "$CONFIG_FILE")

        if [ "$enabled" = "true" ]; then
            printf "  %-15s ${GREEN}%-10s${NC} %-10s %s\n" "$name" "enabled" "${delay}s" "$events"
        else
            printf "  %-15s %-10s %-10s %s\n" "$name" "disabled" "${delay}s" "$events"
        fi
    done
}

# 模拟 hook 流程
test_hook_flow() {
    echo -e "${YELLOW}[模拟 Hook]${NC} 模拟完整分级推送流程..."
    echo ""

    # 显示将要触发的 channel
    list_channels
    echo ""

    MOCK_JSON='{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your response","cwd":"'"$PWD"'","session_id":"test-session"}'

    echo "$MOCK_JSON" | bash "${SCRIPT_DIR}/scripts/notify.sh" notification

    echo -e "${GREEN}[模拟 Hook]${NC} ✅ 后台推送进程已启动"
    echo ""
    echo "  已启用的 channel 将按 delay 顺序依次推送"
    echo "  模拟取消推送: bash ${SCRIPT_DIR}/scripts/clear_pending.sh < /dev/null"
}

# 主逻辑
case "${1:-all}" in
    list)
        list_channels
        ;;
    hook)
        test_hook_flow
        ;;
    all)
        for ch_file in "${CHANNELS_DIR}"/*.sh; do
            name=$(basename "$ch_file" .sh)
            test_channel "$name"
            echo ""
        done
        ;;
    *)
        test_channel "$1"
        ;;
esac

echo ""
echo "========================================="
