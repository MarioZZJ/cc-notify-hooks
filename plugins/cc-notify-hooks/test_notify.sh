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
#   bash test_notify.sh user-input    # 验证 request_user_input dispatcher 与模板
#   bash test_notify.sh state         # 验证 session scoped 状态、去重与清理
#   bash test_notify.sh render        # 验证通知标题和正文模板
#   bash test_notify.sh agents        # 验证 Reasonix / dsh 的 agent 识别与事件字段

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
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
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
elif [ -f "${HOME}/.claude/hooks/notify.json" ]; then
    CONFIG_FILE="${HOME}/.claude/hooks/notify.json"
fi

echo "========================================="
echo "  cc-notify-hooks - 连通性测试"
echo "========================================="
echo ""

COMMAND="${1:-all}"

if [ -z "$CONFIG_FILE" ] &&
   [ "$COMMAND" != "codex-plugin-hooks" ] &&
   [ "$COMMAND" != "user-input" ] &&
   [ "$COMMAND" != "state" ] &&
   [ "$COMMAND" != "render" ]; then
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

# 验证 Codex 插件打包 hook 能从任意会话 cwd 使用 runtime 路径变量
test_codex_plugin_hooks() {
    (
        set -euo pipefail
        echo -e "${YELLOW}[Codex Plugin Hooks]${NC} 验证 PLUGIN_ROOT、PLUGIN_DATA 与自定义 CODEX_HOME..."

        local tmp_base tmp_root tmp_home plugin_data custom_codex_home
        local stop_cmd clear_cmd pre_cmd post_cmd out
        tmp_base="${TMPDIR:-/tmp}"
        tmp_root=$(mktemp -d "${tmp_base%/}/cc-notify-hooks.XXXXXX")
        trap 'rm -rf "$tmp_root"' EXIT
        tmp_home="${tmp_root}/home"
        plugin_data="${tmp_root}/plugin-data"
        custom_codex_home="${tmp_root}/custom-codex"
        mkdir -p "$tmp_home" "$plugin_data/state" "${custom_codex_home}/cc-notify-hooks"
        printf '%s\n' '{"channels":{},"rate_limit":10}' > "${plugin_data}/notify.json"
        printf '%s\n' '{"channels":{},"rate_limit":10}' > "${custom_codex_home}/cc-notify-hooks/notify.json"

        stop_cmd=$(jq -r '.hooks.Stop[0].hooks[0].command' "${SCRIPT_DIR}/hooks/codex-hooks.json")
        clear_cmd=$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "${SCRIPT_DIR}/hooks/codex-hooks.json")
        pre_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "${SCRIPT_DIR}/hooks/codex-hooks.json")
        post_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "${SCRIPT_DIR}/hooks/codex-hooks.json")

        cd "$tmp_base"
        printf '%s' '{"hook_event_name":"Stop","session_id":"codex-plugin-test","cwd":"'"$tmp_base"'"}' \
            | HOME="$tmp_home" CODEX_HOME="$custom_codex_home" PLUGIN_ROOT="$SCRIPT_DIR" PLUGIN_DATA="$plugin_data" \
                bash -c "$stop_cmd"

        out=$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"codex-plugin-test","turn_id":"turn-plugin","tool_name":"request_user_input","tool_use_id":"call-plugin","tool_input":{"questions":[{"header":"确认","question":"是否继续？","options":[{"label":"继续"},{"label":"取消"}]}]},"cwd":"'"$tmp_base"'"}' \
            | HOME="$tmp_home" CODEX_HOME="$custom_codex_home" PLUGIN_ROOT="$SCRIPT_DIR" PLUGIN_DATA="$plugin_data" \
                CC_NOTIFY_RENDER_ONLY=1 bash -c "$pre_cmd")

        if [ "$(printf '%s' "$out" | jq -r '.event_kind')" != "user_input" ]; then
            echo -e "${RED}[Codex Plugin Hooks]${NC} PreToolUse 没有通过 PLUGIN_ROOT 执行 dispatcher"
            return 1
        fi

        touch "${plugin_data}/state/pending_codex-plugin-test_user_input_call-plugin_1_1"
        printf '%s' '{"hook_event_name":"PostToolUse","session_id":"codex-plugin-test","tool_name":"request_user_input","tool_use_id":"call-plugin"}' \
            | HOME="$tmp_home" CODEX_HOME="$custom_codex_home" PLUGIN_ROOT="$SCRIPT_DIR" PLUGIN_DATA="$plugin_data" \
                bash -c "$post_cmd"
        if compgen -G "${plugin_data}/state/pending_codex-plugin-test_user_input_*" >/dev/null; then
            echo -e "${RED}[Codex Plugin Hooks]${NC} PostToolUse 没有清理 user_input pending"
            return 1
        fi

        printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"codex-plugin-test","prompt":"hello"}' \
            | HOME="$tmp_home" CODEX_HOME="$custom_codex_home" PLUGIN_ROOT="$SCRIPT_DIR" PLUGIN_DATA="$plugin_data" \
                bash -c "$clear_cmd"

        if [ ! -f "${plugin_data}/state/last_codex-plugin-test_stop" ]; then
            echo -e "${RED}[Codex Plugin Hooks]${NC} Stop hook 没有写入 PLUGIN_DATA state"
            return 1
        fi

        printf '%s' '{"hook_event_name":"Stop","session_id":"standalone-test","cwd":"'"$tmp_base"'"}' \
            | HOME="$tmp_home" CODEX_HOME="$custom_codex_home" CC_NOTIFY_STATE_DIR="${tmp_root}/standalone-state" \
                bash "${SCRIPT_DIR}/scripts/notify.sh" stop
        if [ ! -f "${tmp_root}/standalone-state/last_standalone-test_stop" ]; then
            echo -e "${RED}[Codex Plugin Hooks]${NC} notify.sh 没有读取自定义 CODEX_HOME 配置"
            return 1
        fi

        echo -e "${GREEN}[Codex Plugin Hooks]${NC} ✅ runtime 路径与自定义 CODEX_HOME 符合预期"
    )
}

test_user_input_flow() {
    (
        set -euo pipefail
        echo -e "${YELLOW}[request_user_input]${NC} 验证 dispatcher、模板与安静降级..."

        local tmp_base tmp_root state_dir out markdown fallback_out empty_out invalid_out no_jq_out
        local capture_file feishu_payload discord_payload
        local bash_bin minimal_bin
        tmp_base="${TMPDIR:-/tmp}"
        tmp_root=$(mktemp -d "${tmp_base%/}/cc-notify-hooks-user-input.XXXXXX")
        trap 'rm -rf "$tmp_root"' EXIT
        state_dir="${tmp_root}/state"
        mkdir -p "$state_dir"

        out=$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"session-user-input","turn_id":"turn-user-input","tool_name":"request_user_input","tool_use_id":"call-user-input","tool_input":{"questions":[{"header":"范围","question":"这次修复覆盖什么？","options":[{"label":"完整修复"},{"label":"最小补丁"}]},{"header":"通知","question":"使用哪个渠道？","options":[{"label":"macOS"},{"label":"Bark"}]}]},"cwd":"/tmp/demo-project","model":"gpt-5.5"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/pre_tool_use.sh")

        if [ "$(printf '%s' "$out" | jq -r '.title')" != "Codex · 需要回复 🔔" ] ||
           [ "$(printf '%s' "$out" | jq -r '.summary_short')" != "范围" ] ||
           [ "$(printf '%s' "$out" | jq -r '.event_kind')" != "user_input" ] ||
           [ "$(printf '%s' "$out" | jq -r '.question_count')" != "2" ] ||
           [ "$(printf '%s' "$out" | jq -r '.option_labels | join(",")')" != "完整修复,最小补丁" ] ||
           [[ "$(printf '%s' "$out" | jq -r '.body')" != *"2 个问题 · Session session-"* ]]; then
            echo -e "${RED}[request_user_input]${NC} 结构化通知字段错误: $out"
            return 1
        fi

        source "${SCRIPT_DIR}/scripts/lib/notify_format.sh"
        markdown=$(notify_long_markdown "$out")
        if [[ "$markdown" != *"**问题数**: 2"* ]] ||
           [[ "$markdown" != *"**选项**: 完整修复 / 最小补丁"* ]] ||
           [[ "$markdown" != *"**Session**: session-user-input"* ]] ||
           [[ "$markdown" != *"/tmp/demo-project"* ]]; then
            echo -e "${RED}[request_user_input]${NC} 长通知字段错误: $markdown"
            return 1
        fi

        capture_file="${tmp_root}/channel-payload.json"
        curl() {
            local previous="" argument
            for argument in "$@"; do
                if [ "$previous" = "-d" ]; then
                    printf '%s' "$argument" > "$capture_file"
                    return 0
                fi
                previous="$argument"
            done
            return 0
        }

        source "${SCRIPT_DIR}/scripts/channels/feishu.sh"
        send_feishu "$(printf '%s' "$out" | jq -r '.title')" "$(printf '%s' "$out" | jq -r '.body')" '{"webhook":"https://example.invalid","format":"card"}' "$out"
        feishu_payload=$(cat "$capture_file")
        if ! printf '%s' "$feishu_payload" | jq -e '
            .card.elements[1].fields as $fields
            | any($fields[]; .text.content == "**问题数**\n2")
              and any($fields[]; .text.content == "**选项**\n完整修复 / 最小补丁")
              and any($fields[]; .text.content == "**Session**\nsession-user-input")
        ' >/dev/null; then
            echo -e "${RED}[request_user_input]${NC} 飞书卡片缺少结构化问题字段: $feishu_payload"
            return 1
        fi

        source "${SCRIPT_DIR}/scripts/channels/discord.sh"
        send_discord "$(printf '%s' "$out" | jq -r '.title')" "$(printf '%s' "$out" | jq -r '.body')" '{"webhook":"https://example.invalid","format":"embed"}' "$out"
        discord_payload=$(cat "$capture_file")
        if ! printf '%s' "$discord_payload" | jq -e '
            .embeds[0].fields as $fields
            | any($fields[]; .name == "问题数" and .value == "2")
              and any($fields[]; .name == "选项" and .value == "完整修复 / 最小补丁")
              and any($fields[]; .name == "Session" and .value == "session-user-input")
        ' >/dev/null; then
            echo -e "${RED}[request_user_input]${NC} Discord embed 缺少结构化问题字段: $discord_payload"
            return 1
        fi

        fallback_out=$(printf '%s' '{"hook_event_name":"PreToolUse","turn_id":"turn-only-123","tool_name":"request_user_input","tool_use_id":"call-fallback","tool_input":{"questions":[{"header":"","question":"请选择修复范围","options":[{"label":"完整"},{"label":"最小"}]}]},"cwd":"/tmp/demo-project"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/pre_tool_use.sh")
        if [ "$(printf '%s' "$fallback_out" | jq -r '.summary_short')" != "请选择修复范围" ] ||
           [ "$(printf '%s' "$fallback_out" | jq -r '.session_short')" != "turn-onl" ]; then
            echo -e "${RED}[request_user_input]${NC} question/turn_id fallback 错误: $fallback_out"
            return 1
        fi

        touch \
            "${state_dir}/pending_session-a_notification_call-a_1_1" \
            "${state_dir}/pending_session-b_notification_call-b_1_1"
        printf '%s' '{"hook_event_name":"PreToolUse","session_id":"session-a","tool_name":"Bash","tool_input":{"command":"true"}}' \
            | CC_NOTIFY_STATE_DIR="$state_dir" bash "${SCRIPT_DIR}/scripts/pre_tool_use.sh"
        if compgen -G "${state_dir}/pending_session-a_*" >/dev/null ||
           ! compgen -G "${state_dir}/pending_session-b_*" >/dev/null; then
            echo -e "${RED}[request_user_input]${NC} 普通 PreToolUse 没有按 session 清理"
            return 1
        fi

        empty_out=$(printf '%s' '{"hook_event_name":"PreToolUse","session_id":"empty","tool_name":"request_user_input","tool_input":{"questions":[]}}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/pre_tool_use.sh")
        invalid_out=$(printf '%s' '{invalid json' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/pre_tool_use.sh")

        bash_bin=$(command -v bash)
        minimal_bin="${tmp_root}/minimal-bin"
        mkdir -p "$minimal_bin"
        ln -s "$(command -v cat)" "${minimal_bin}/cat"
        ln -s "$(command -v dirname)" "${minimal_bin}/dirname"
        no_jq_out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"request_user_input","tool_input":{"questions":[{"question":"test"}]}}' \
            | PATH="$minimal_bin" "$bash_bin" "${SCRIPT_DIR}/scripts/pre_tool_use.sh")

        if [ -n "$empty_out" ] || [ -n "$invalid_out" ] || [ -n "$no_jq_out" ]; then
            echo -e "${RED}[request_user_input]${NC} 空问题、非法 JSON 或缺少 jq 时不应输出"
            return 1
        fi

        echo -e "${GREEN}[request_user_input]${NC} ✅ dispatcher 与通知模板符合预期"
    )
}

test_session_state() {
    (
        set -euo pipefail
        shopt -s nullglob
        echo -e "${YELLOW}[Session State]${NC} 验证 pending、rate-limit、去重与 /exit 隔离..."

        local tmp_base tmp_root state_dir config_file event_a event_a_new event_b
        local first_pending repeated_pending new_pending
        tmp_base="${TMPDIR:-/tmp}"
        tmp_root=$(mktemp -d "${tmp_base%/}/cc-notify-hooks-state.XXXXXX")
        trap 'rm -rf "$tmp_root"' EXIT
        state_dir="${tmp_root}/state"
        config_file="${tmp_root}/notify.json"
        mkdir -p "$state_dir"
        printf '%s\n' '{"channels":{},"rate_limit":10}' > "$config_file"

        event_a='{"hook_event_name":"PreToolUse","session_id":"session-a","turn_id":"turn-a","tool_name":"request_user_input","tool_use_id":"call-a","tool_input":{"questions":[{"header":"A","question":"Question A","options":[{"label":"Yes"},{"label":"No"}]}]},"cwd":"/tmp/project-a"}'
        event_a_new=$(printf '%s' "$event_a" | jq -c '.tool_use_id = "call-a-new"')
        event_b=$(printf '%s' "$event_a" | jq -c '.session_id = "session-b" | .turn_id = "turn-b" | .tool_use_id = "call-b" | .tool_input.questions[0].header = "B"')

        printf '%s' "$event_a" \
            | CC_NOTIFY_CONFIG="$config_file" CC_NOTIFY_STATE_DIR="$state_dir" \
                bash "${SCRIPT_DIR}/scripts/notify.sh" notification user_input
        first_pending=$(compgen -G "${state_dir}/pending_session-a_user_input_*" | head -n 1)
        [ -n "$first_pending" ] || { echo -e "${RED}[Session State]${NC} session A 未创建 pending"; return 1; }

        printf '%s' "$event_a" \
            | CC_NOTIFY_CONFIG="$config_file" CC_NOTIFY_STATE_DIR="$state_dir" \
                bash "${SCRIPT_DIR}/scripts/notify.sh" notification user_input
        repeated_pending=$(compgen -G "${state_dir}/pending_session-a_user_input_*" | head -n 1)
        if [ "$repeated_pending" != "$first_pending" ]; then
            echo -e "${RED}[Session State]${NC} 相同 tool_use_id 没有去重"
            return 1
        fi

        printf '%s' "$event_a_new" \
            | CC_NOTIFY_CONFIG="$config_file" CC_NOTIFY_STATE_DIR="$state_dir" \
                bash "${SCRIPT_DIR}/scripts/notify.sh" notification user_input
        new_pending=$(compgen -G "${state_dir}/pending_session-a_user_input_*" | head -n 1)
        if [ "$new_pending" = "$first_pending" ]; then
            echo -e "${RED}[Session State]${NC} 不同 tool_use_id 被十秒限流吞掉"
            return 1
        fi

        printf '%s' "$event_b" \
            | CC_NOTIFY_CONFIG="$config_file" CC_NOTIFY_STATE_DIR="$state_dir" \
                bash "${SCRIPT_DIR}/scripts/notify.sh" notification user_input
        if ! compgen -G "${state_dir}/pending_session-a_user_input_*" >/dev/null ||
           ! compgen -G "${state_dir}/pending_session-b_user_input_*" >/dev/null ||
           [ ! -f "${state_dir}/last_session-a_user_input" ] ||
           [ ! -f "${state_dir}/last_session-b_user_input" ]; then
            echo -e "${RED}[Session State]${NC} 两个 session 的 pending/rate 状态没有隔离"
            return 1
        fi

        printf '%s' '{"hook_event_name":"PostToolUse","session_id":"session-a","tool_name":"request_user_input","tool_use_id":"call-a-new"}' \
            | CC_NOTIFY_STATE_DIR="$state_dir" bash "${SCRIPT_DIR}/scripts/clear_pending.sh" user_input
        if compgen -G "${state_dir}/pending_session-a_user_input_*" >/dev/null ||
           ! compgen -G "${state_dir}/pending_session-b_user_input_*" >/dev/null; then
            echo -e "${RED}[Session State]${NC} PostToolUse 清理影响了其他 session"
            return 1
        fi

        printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"session-a","prompt":"/exit"}' \
            | CC_NOTIFY_STATE_DIR="$state_dir" bash "${SCRIPT_DIR}/scripts/clear_pending.sh"
        [ -f "${state_dir}/exiting_session-a" ] || { echo -e "${RED}[Session State]${NC} /exit 未按 session 记录"; return 1; }

        printf '%s' '{"hook_event_name":"Stop","session_id":"session-b","cwd":"/tmp/project-b"}' \
            | CC_NOTIFY_CONFIG="$config_file" CC_NOTIFY_STATE_DIR="$state_dir" \
                bash "${SCRIPT_DIR}/scripts/notify.sh" stop
        [ -f "${state_dir}/last_session-b_stop" ] || { echo -e "${RED}[Session State]${NC} session A 的 /exit 错误抑制了 session B"; return 1; }

        printf '%s' '{"hook_event_name":"Stop","session_id":"session-a","cwd":"/tmp/project-a"}' \
            | CC_NOTIFY_CONFIG="$config_file" CC_NOTIFY_STATE_DIR="$state_dir" \
                bash "${SCRIPT_DIR}/scripts/notify.sh" stop
        if [ -f "${state_dir}/exiting_session-a" ] || [ -f "${state_dir}/last_session-a_stop" ]; then
            echo -e "${RED}[Session State]${NC} /exit Stop 抑制行为错误"
            return 1
        fi

        echo -e "${GREEN}[Session State]${NC} ✅ session 状态、精确去重与清理符合预期"
    )
}

test_render_templates() {
    echo -e "${YELLOW}[模板渲染]${NC} 验证短通知和结构化长通知字段..."

    local out title body summary event_name tool_name status_label
    out=$(
        printf '%s' '{"hook_event_name":"Stop","session_id":"render-codex","cwd":"/tmp/demo-project","model":"gpt-5.5","last_assistant_message":"已完成训练状态检查\n\n后续细节不会进通知。"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" stop
    )
    title=$(echo "$out" | jq -r '.title')
    body=$(echo "$out" | jq -r '.body')
    summary=$(echo "$out" | jq -r '.summary_short')
    event_name=$(echo "$out" | jq -r '.event_name')
    tool_name=$(echo "$out" | jq -r '.tool_name')

    if [ "$title" != "Codex · 任务完成 ✅" ]; then
        echo -e "${RED}[模板渲染]${NC} Codex Stop 标题错误: $title"
        return 1
    fi
    if [[ "$body" != "[demo-project] 已完成训练状态检查"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Codex Stop 正文错误: $body"
        return 1
    fi
    if [ "$summary" != "已完成训练状态检查" ] || [ "$event_name" != "Stop" ] || [ -n "$tool_name" ]; then
        echo -e "${RED}[模板渲染]${NC} Codex Stop 结构化字段错误: $out"
        return 1
    fi
    if [[ "$body" == *"Claude 已完成工作"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Codex Stop 仍包含旧文案: $body"
        return 1
    fi
    if [[ "$body" == *"gpt-5.5"* ]] || [[ "$body" == *"on-request"* ]]; then
        echo -e "${RED}[模板渲染]${NC} 短通知正文不应包含模型或权限: $body"
        return 1
    fi

    out=$(
        printf '%s' '{"hook_event_name":"Stop","session_id":"render-claude-stop","transcript_path":"/Users/test/.claude/projects/demo/session.jsonl","cwd":"/tmp/demo-project","model":"claude-sonnet-4-5","last_assistant_message":"Claude 侧任务也完成了。"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" stop
    )
    title=$(echo "$out" | jq -r '.title')
    body=$(echo "$out" | jq -r '.body')

    if [ "$title" != "Claude Code · 任务完成 ✅" ]; then
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
    status_label=$(echo "$out" | jq -r '.status_label')

    if [ "$title" != "Claude Code · 等待响应 ⏳" ]; then
        echo -e "${RED}[模板渲染]${NC} Claude Notification 标题错误: $title"
        return 1
    fi
    if [ "$status_label" != "等待响应 ⏳" ]; then
        echo -e "${RED}[模板渲染]${NC} Claude Notification 状态错误: $status_label"
        return 1
    fi
    if [[ "$body" != "[demo-project] Claude is waiting for your response"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Claude Notification 正文错误: $body"
        return 1
    fi

    out=$(
        printf '%s' '{"hook_event_name":"PermissionRequest","session_id":"render-codex-perm","cwd":"/tmp/demo-project","model":"gpt-5.5","permission_mode":"on-request","tool_name":"Bash","prompt":"请求执行 Bash 命令：git push origin main\n\n该操作会推送远端分支。"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" notification
    )
    title=$(echo "$out" | jq -r '.title')
    body=$(echo "$out" | jq -r '.body')
    summary=$(echo "$out" | jq -r '.summary_short')
    tool_name=$(echo "$out" | jq -r '.tool_name')

    if [ "$title" != "Codex · 需要确认 🔔" ]; then
        echo -e "${RED}[模板渲染]${NC} Codex Permission 标题错误: $title"
        return 1
    fi
    if [ "$summary" != "请求执行 Bash 命令：git push origin main" ] || [ "$tool_name" != "Bash" ]; then
        echo -e "${RED}[模板渲染]${NC} Codex Permission 摘要或工具错误: $out"
        return 1
    fi
    if [[ "$body" != "[demo-project] 请求执行 Bash 命令：git push origin main · Bash" ]]; then
        echo -e "${RED}[模板渲染]${NC} Codex Permission 短正文错误: $body"
        return 1
    fi
    if [[ "$body" == *"on-request"* ]]; then
        echo -e "${RED}[模板渲染]${NC} Permission mode 不应进入短正文: $body"
        return 1
    fi

    local markdown
    source "${SCRIPT_DIR}/scripts/lib/notify_format.sh"
    markdown=$(notify_long_markdown "$out")
    if [[ "$markdown" != *"请求执行 Bash 命令：git push origin main"* ]] ||
       [[ "$markdown" != *"**项目**: demo-project"* ]] ||
       [[ "$markdown" != *"**事件**: PermissionRequest"* ]] ||
       [[ "$markdown" != *"**工具**: Bash"* ]] ||
       [[ "$markdown" != *"**Session**: render-c"* ]] ||
       [[ "$markdown" != *"gpt-5.5 · /tmp/demo-project"* ]]; then
        echo -e "${RED}[模板渲染]${NC} 长通知 Markdown 错误: $markdown"
        return 1
    fi
    if [[ "$markdown" == *"on-request"* ]] || [[ "$markdown" == *"cc-notify-hooks ·"* ]]; then
        echo -e "${RED}[模板渲染]${NC} 长通知不应包含权限或旧 note: $markdown"
        return 1
    fi

    echo -e "${GREEN}[模板渲染]${NC} ✅ 短通知和长通知字段符合预期"
}

# 验证 Reasonix / dsh 的 agent 识别与事件字段兼容
test_agent_detection() {
    echo -e "${YELLOW}[Agent 识别]${NC} 验证 Reasonix / dsh 的 agent 识别与事件字段..."

    local out title body summary event_name

    # Reasonix 插件导入格式（Claude 形状 payload + REASONIX_PLUGIN_ROOT 环境）
    out=$(
        printf '%s' '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"approval needed: bash git push origin main","session_id":"reasonix-session-1","cwd":"/tmp/demo-project"}' \
            | REASONIX_PLUGIN_ROOT="/fake/reasonix/plugins/cc-notify-hooks" \
                CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" notification
    )
    title=$(echo "$out" | jq -r '.title')
    status_label=$(echo "$out" | jq -r '.status_label')
    summary=$(echo "$out" | jq -r '.summary_short')
    if [ "$title" != "Reasonix · 需要确认 🔔" ] || [ "$status_label" != "需要确认 🔔" ] ||
       [ "$summary" != "approval needed: bash git push origin main" ]; then
        echo -e "${RED}[Agent 识别]${NC} Reasonix Notification 识别或模板错误: $out"
        return 1
    fi

    # Reasonix 原生格式 payload（event / sessionId / lastAssistantText）
    out=$(
        printf '%s' '{"event":"Stop","sessionId":"reasonix-session-2","cwd":"/tmp/demo-project","lastAssistantText":"已完成检查","turn":1}' \
            | REASONIX_PLUGIN_ROOT="/fake/reasonix/plugins/cc-notify-hooks" \
                CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" stop
    )
    title=$(echo "$out" | jq -r '.title')
    summary=$(echo "$out" | jq -r '.summary_short')
    if [ "$title" != "Reasonix · 任务完成 ✅" ] || [ "$summary" != "已完成检查" ]; then
        echo -e "${RED}[Agent 识别]${NC} Reasonix 原生 Stop 字段错误: $out"
        return 1
    fi

    # dsh 插件环境（DSH_CC_NOTIFY）Stop 事件
    out=$(
        printf '%s' '{"hook_event_name":"Stop","session_id":"dsh-session-1","cwd":"/tmp/demo-project","stop_hook_active":false}' \
            | DSH_CC_NOTIFY=1 CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" stop
    )
    title=$(echo "$out" | jq -r '.title')
    body=$(echo "$out" | jq -r '.body')
    if [ "$title" != "dsh · 任务完成 ✅" ] || [[ "$body" != "[demo-project] 任务已完成"* ]]; then
        echo -e "${RED}[Agent 识别]${NC} dsh Stop 识别或模板错误: $out"
        return 1
    fi

    # 显式 CC_NOTIFY_AGENT 覆盖优先于环境特征
    out=$(
        printf '%s' '{"hook_event_name":"Stop","session_id":"x","cwd":"/tmp/demo-project"}' \
            | REASONIX_PLUGIN_ROOT="/fake" DSH_CC_NOTIFY=1 CC_NOTIFY_AGENT="Custom Agent" \
                CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" stop
    )
    title=$(echo "$out" | jq -r '.title')
    if [ "$title" != "Custom Agent · 任务完成 ✅" ]; then
        echo -e "${RED}[Agent 识别]${NC} CC_NOTIFY_AGENT 覆盖未生效: $out"
        return 1
    fi

    # 无环境特征时仍按旧逻辑识别（Notification → Claude Code）
    out=$(
        printf '%s' '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"waiting","session_id":"c","cwd":"/tmp/demo-project"}' \
            | CC_NOTIFY_RENDER_ONLY=1 bash "${SCRIPT_DIR}/scripts/notify.sh" notification
    )
    title=$(echo "$out" | jq -r '.title')
    if [ "$title" != "Claude Code · 等待响应 ⏳" ]; then
        echo -e "${RED}[Agent 识别]${NC} 无环境特征时 Claude Notification 识别错误: $out"
        return 1
    fi

    echo -e "${GREEN}[Agent 识别]${NC} ✅ Reasonix / dsh / 覆盖顺序符合预期"
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
    user-input)
        test_user_input_flow
        ;;
    state)
        test_session_state
        ;;
    render)
        test_render_templates
        ;;
    agents)
        test_agent_detection
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
