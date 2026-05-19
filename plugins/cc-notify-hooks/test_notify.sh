#!/usr/bin/env bash
#
# 测试脚本 - 验证各渠道推送连通性
#
# 用法：
#   bash test_notify.sh              # 测试所有已启用 channel
#   bash test_notify.sh bark         # 测试单个 channel
#   bash test_notify.sh hook         # 模拟完整 hook 流程（Claude Code 字段格式）
#   bash test_notify.sh codex        # 模拟 Codex CLI 的 PermissionRequest 事件（prompt 字段）
#   bash test_notify.sh list         # 列出已启用 channel
#   bash test_notify.sh codex-plugin-hooks  # 验证 Codex 插件 hook 不依赖会话 cwd
#   bash test_notify.sh render        # 验证通知标题和正文模板

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHANNELS_DIR="${SCRIPT_DIR}/scripts/channels"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 查找配置文件（顺序与 scripts/notify.sh 保持一致）
CONFIG_FILE=""
if [ -n "${CC_NOTIFY_CONFIG:-}" ] && [ -f "${CC_NOTIFY_CONFIG}" ]; then
    CONFIG_FILE="${CC_NOTIFY_CONFIG}"
elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -f "${CLAUDE_PLUGIN_DATA}/notify.json" ]; then
    CONFIG_FILE="${CLAUDE_PLUGIN_DATA}/notify.json"
elif [ -f "${HOME}/.codex/cc-notify-hooks/notify.json" ]; then
    CONFIG_FILE="${HOME}/.codex/cc-notify-hooks/notify.json"
elif [ -f "${HOME}/.claude/hooks/notify.json" ]; then
    CONFIG_FILE="${HOME}/.claude/hooks/notify.json"
fi

echo "========================================="
echo "  cc-notify-hooks - 连通性测试"
echo "========================================="
echo ""

COMMAND="${1:-all}"

if [ -z "$CONFIG_FILE" ] && [ "$COMMAND" != "codex-plugin-hooks" ] && [ "$COMMAND" != "render" ]; then
    echo -e "${RED}未找到配置文件${NC}"
    echo "  请先运行 bash install.sh 或复制 config/notify.example.json 到"
    echo "  ~/.claude/hooks/notify.json"
    exit 1
fi

if [ -n "$CONFIG_FILE" ]; then
    echo -e "  配置文件: ${CYAN}${CONFIG_FILE}${NC}"
    echo ""
fi

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

# 模拟 Codex CLI hook 流程
test_codex_flow() {
    echo -e "${YELLOW}[模拟 Codex Hook]${NC} 模拟 Codex PermissionRequest 事件..."
    echo "  字段差异：Codex 用 prompt 字段而非 message，事件名 PermissionRequest"
    echo ""

    list_channels
    echo ""

    # Codex stdin 格式：用 prompt 字段而非 message，hook_event_name = PermissionRequest
    MOCK_JSON='{"hook_event_name":"PermissionRequest","prompt":"Codex 请求执行 Bash 命令","cwd":"'"$PWD"'","session_id":"codex-test-session","model":"gpt-5.5"}'

    echo "$MOCK_JSON" | bash "${SCRIPT_DIR}/scripts/notify.sh" notification

    echo -e "${GREEN}[模拟 Codex Hook]${NC} ✅ 后台推送进程已启动"
    echo ""
    echo "  已启用的 channel 将按 delay 顺序依次推送"
    echo "  模拟取消推送（Codex UserPromptSubmit）："
    echo "    echo '{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hello\"}' | bash ${SCRIPT_DIR}/scripts/clear_pending.sh"
}

# 验证 Codex 插件打包 hook 能从任意会话 cwd 找到插件缓存里的脚本
test_codex_plugin_hooks() {
    echo -e "${YELLOW}[Codex Plugin Hooks]${NC} 验证插件 hook 命令不依赖当前目录..."

    local tmp_base tmp_home plugin_parent plugin_root stop_cmd clear_cmd
    tmp_base="${TMPDIR:-/tmp}"
    tmp_home=$(mktemp -d "${tmp_base%/}/cc-notify-hooks.XXXXXX")
    plugin_parent="${tmp_home}/.codex/plugins/cache/local/cc-notify-hooks"
    plugin_root="${plugin_parent}/local"
    mkdir -p "$plugin_parent"
    ln -s "$SCRIPT_DIR" "$plugin_root"

    stop_cmd=$(jq -r '.hooks.Stop[0].hooks[0].command' "${SCRIPT_DIR}/hooks/codex-hooks.json")
    clear_cmd=$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "${SCRIPT_DIR}/hooks/codex-hooks.json")

    (
        cd "$tmp_base"
        printf '%s' '{"hook_event_name":"Stop","session_id":"codex-plugin-test","cwd":"'"$tmp_base"'"}' \
            | HOME="$tmp_home" bash -lc "$stop_cmd"
        printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"hello","cwd":"'"$tmp_base"'"}' \
            | HOME="$tmp_home" bash -lc "$clear_cmd"
    )

    if [ ! -f "${tmp_home}/.claude/hooks/state/last_stop" ]; then
        echo -e "${RED}[Codex Plugin Hooks]${NC} stop hook 没有执行到 notify.sh"
        rm -rf "$tmp_home"
        return 1
    fi

    rm -rf "$tmp_home"
    echo -e "${GREEN}[Codex Plugin Hooks]${NC} ✅ 插件 hook 可从任意 cwd 执行"
}

test_render_templates() {
    echo -e "${YELLOW}[模板渲染]${NC} 验证 Agent 名和 Stop 摘要..."

    local out title body
    out=$(
        printf '%s' '{"hook_event_name":"Stop","session_id":"render-codex","cwd":"/tmp/demo-project","model":"gpt-5.5","last_assistant_message":"已完成训练状态检查\n\n后续细节不会进通知。"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" stop
    )
    title=$(echo "$out" | jq -r '.title')
    body=$(echo "$out" | jq -r '.body')

    if [ "$title" != "Codex · 任务完成" ]; then
        echo -e "${RED}[模板渲染]${NC} Codex Stop 标题错误: $title"
        return 1
    fi
    if [[ "$body" != "[demo-project] 已完成训练状态检查"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Codex Stop 正文错误: $body"
        return 1
    fi
    if [[ "$body" == *"Claude 已完成工作"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Codex Stop 仍包含旧文案: $body"
        return 1
    fi

    out=$(
        printf '%s' '{"hook_event_name":"Stop","session_id":"render-claude-stop","transcript_path":"/Users/test/.claude/projects/demo/session.jsonl","cwd":"/tmp/demo-project","model":"claude-sonnet-4-5","last_assistant_message":"Claude 侧任务也完成了。"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" stop
    )
    title=$(echo "$out" | jq -r '.title')
    body=$(echo "$out" | jq -r '.body')

    if [ "$title" != "Claude Code · 任务完成" ]; then
        echo -e "${RED}[模板渲染]${NC} Claude Stop 标题错误: $title"
        return 1
    fi
    if [[ "$body" != "[demo-project] Claude 侧任务也完成了。"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Claude Stop 正文错误: $body"
        return 1
    fi

    out=$(
        printf '%s' '{"hook_event_name":"Notification","notification_type":"idle_prompt","session_id":"render-claude","cwd":"/tmp/demo-project","model":"claude-sonnet-4-5","message":"Claude is waiting for your response"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" notification
    )
    title=$(echo "$out" | jq -r '.title')
    body=$(echo "$out" | jq -r '.body')

    if [ "$title" != "Claude Code · 等待响应" ]; then
        echo -e "${RED}[模板渲染]${NC} Claude Notification 标题错误: $title"
        return 1
    fi
    if [[ "$body" != "[demo-project] Claude is waiting for your response"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Claude Notification 正文错误: $body"
        return 1
    fi

    echo -e "${GREEN}[模板渲染]${NC} ✅ 标题和正文模板符合预期"
}

# 主逻辑
case "$COMMAND" in
    list)
        list_channels
        ;;
    hook)
        test_hook_flow
        ;;
    codex)
        test_codex_flow
        ;;
    codex-plugin-hooks)
        test_codex_plugin_hooks
        ;;
    render)
        test_render_templates
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
