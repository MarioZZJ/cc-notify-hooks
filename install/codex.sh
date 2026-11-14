#!/usr/bin/env bash
#
# cc-notify-hooks 独立安装脚本（Codex CLI 分支）
# 部署 scripts/ 到 ~/.codex/cc-notify-hooks/，写入 ~/.codex/hooks.json
#
# 既可被 install.sh 路由调用，也可独立运行：
#   bash install/codex.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
INSTALL_DIR="${CODEX_HOME_DIR}/cc-notify-hooks"
SCRIPTS_DIR="${INSTALL_DIR}/scripts"
STATE_DIR="${INSTALL_DIR}/state"
CONFIG_FILE="${INSTALL_DIR}/notify.json"
HOOKS_FILE="${CODEX_HOME_DIR}/hooks.json"
CODEX_CONFIG="${CODEX_HOME_DIR}/config.toml"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

echo "========================================="
echo "  cc-notify-hooks - Codex CLI 独立安装"
echo "  平台: $(uname -s) $(uname -m)"
echo "========================================="
echo ""

# ============================================================
#  [1/4] 检查依赖
# ============================================================
echo -e "${YELLOW}[1/4]${NC} 检查依赖..."
MISSING_DEP=0
for cmd in jq curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "  ${RED}✗${NC} $cmd 未安装"
        MISSING_DEP=1
    else
        echo -e "  ${GREEN}✓${NC} $cmd"
    fi
done
if [ "$MISSING_DEP" -eq 1 ]; then
    echo ""
    echo "  请先安装缺失的依赖："
    if $IS_MACOS; then
        echo "  macOS:         brew install jq curl"
    else
        echo "  Debian/Ubuntu: sudo apt install -y jq curl"
        echo "  CentOS/RHEL:   sudo yum install -y jq curl"
    fi
    exit 1
fi

# Codex 安装提示（不强制，用户可以先装 hooks）
if ! command -v codex &>/dev/null && [ ! -x "/Applications/Codex.app/Contents/Resources/codex" ]; then
    echo -e "  ${YELLOW}⚠${NC} 未检测到 Codex CLI（继续安装，请稍后再装 Codex）"
fi

# ============================================================
#  [2/4] 交互式配置
# ============================================================
echo -e "${YELLOW}[2/4]${NC} 配置推送渠道..."
echo ""

# Channel 定义：name|display_name|default_delay|credential_fields
CHANNEL_DEFS=(
    "macos|macOS 系统通知|3|"
    "bark|Bark (iOS/macOS/Android)|15|key:Bark Key;server:Bark Server [https://api.day.app]"
    "telegram|Telegram Bot|5|bot_token:Bot Token;chat_id:Chat ID"
    "pushover|Pushover|15|app_token:App Token;user_key:User Key"
    "ntfy|ntfy (开源推送)|15|topic:Topic;server:Server [https://ntfy.sh]"
    "gotify|Gotify (自建推送)|15|server:Server URL;app_token:App Token"
    "wechat|企业微信|300|webhook:Webhook URL"
    "feishu|飞书|300|webhook:Webhook URL"
    "dingtalk|钉钉|300|webhook:Webhook URL"
    "slack|Slack|300|webhook:Webhook URL"
    "discord|Discord|300|webhook:Webhook URL"
)

_read_json() {
    local key="$1" default="$2"
    if [ -f "$CONFIG_FILE" ]; then
        local val
        val=$(jq -r "$key // empty" "$CONFIG_FILE" 2>/dev/null) || true
        if [ -n "$val" ] && [ "$val" != "null" ]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

# 复用 Claude 配置（如果已有）
CLAUDE_CONFIG="${HOME}/.claude/hooks/notify.json"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$CLAUDE_CONFIG" ]; then
    echo -e "  ${CYAN}检测到 Claude Code 配置，可直接复用${NC}"
    printf "  复用 $CLAUDE_CONFIG ? [Y/n]: "
    read -r reuse
    if [[ ! "$reuse" =~ ^[Nn] ]]; then
        mkdir -p "$INSTALL_DIR"
        cp "$CLAUDE_CONFIG" "$CONFIG_FILE"
        echo -e "  ${GREEN}✓${NC} 已复用 Claude 配置"
        echo ""
    fi
fi

if [ -f "$CONFIG_FILE" ]; then
    echo -e "  ${CYAN}检测到已有配置 ($CONFIG_FILE)${NC}"
    echo ""
fi

# 列出 channel 让用户选择
echo "  可用的通知渠道："
echo ""
idx=1
for def in "${CHANNEL_DEFS[@]}"; do
    IFS='|' read -r name display delay _fields <<< "$def"
    current_enabled=$(_read_json ".channels.${name}.enabled" "false")
    if [ "$current_enabled" = "true" ]; then
        mark="${GREEN}✓${NC}"
    else
        mark=" "
    fi
    if [ "$name" = "macos" ] && $IS_MACOS && [ "$current_enabled" = "false" ] && [ ! -f "$CONFIG_FILE" ]; then
        mark="${GREEN}✓${NC}"
    fi
    printf "  %s [%b] %2d. %-30s (默认延迟 %ss)\n" "" "$mark" "$idx" "$display" "$delay"
    idx=$((idx + 1))
done
echo ""
echo -e "  ${CYAN}输入编号启用渠道（逗号分隔，如 1,2,7），直接回车保持当前配置${NC}"

printf "  选择: "
read -r selection

ENABLED_CHANNELS='{}'
if [ -n "$selection" ]; then
    IFS=',' read -ra NUMS <<< "$selection"
    for num in "${NUMS[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#CHANNEL_DEFS[@]} ]; then
            IFS='|' read -r name _ _ _ <<< "${CHANNEL_DEFS[$((num - 1))]}"
            ENABLED_CHANNELS=$(jq --arg name "$name" '.[$name] = true' <<< "$ENABLED_CHANNELS")
        fi
    done
else
    if [ -f "$CONFIG_FILE" ]; then
        ENABLED_CHANNELS=$(jq '.channels // {} | with_entries(select(.value.enabled == true)) | map_values(true)' "$CONFIG_FILE")
    fi
    if $IS_MACOS && [ "$(jq 'length' <<< "$ENABLED_CHANNELS")" -eq 0 ]; then
        ENABLED_CHANNELS='{"macos":true}'
    fi
fi

echo ""

# 收集凭证
CHANNEL_CONFIGS='{}'

for def in "${CHANNEL_DEFS[@]}"; do
    IFS='|' read -r name display delay fields <<< "$def"

    if ! jq -e --arg name "$name" '.[$name] == true' <<< "$ENABLED_CHANNELS" >/dev/null; then
        continue
    fi
    if [ -z "$fields" ]; then
        continue
    fi

    echo -e "  ${CYAN}配置 ${display}:${NC}"

    IFS=';' read -ra FIELD_DEFS <<< "$fields"
    for fdef in "${FIELD_DEFS[@]}"; do
        IFS=':' read -r fkey fdesc <<< "$fdef"

        default_hint=""
        if [[ "$fdesc" =~ \[(.+)\] ]]; then
            default_hint="${BASH_REMATCH[1]}"
            fdesc=$(echo "$fdesc" | sed 's/ *\[.*\]//')
        fi

        current=$(_read_json ".channels.${name}.${fkey}" "$default_hint")
        if [ -n "$current" ]; then
            if [ ${#current} -gt 20 ]; then
                hint="${current:0:20}..."
            else
                hint="$current"
            fi
        else
            hint="必填"
        fi

        printf "    %s [%s]: " "$fdesc" "$hint"
        read -r input
        CHANNEL_CONFIGS=$(jq --arg name "$name" --arg key "$fkey" --arg value "${input:-$current}" \
            '.[$name][$key] = $value' <<< "$CHANNEL_CONFIGS")
    done
    echo ""
done

# 构建配置 JSON
CONFIG_JSON='{"channels":{},"rate_limit":10}'

if [ -f "$CONFIG_FILE" ]; then
    old_rate=$(jq -r '.rate_limit // 10' "$CONFIG_FILE")
    CONFIG_JSON=$(echo "$CONFIG_JSON" | jq --argjson rl "$old_rate" '.rate_limit = $rl')
fi

for def in "${CHANNEL_DEFS[@]}"; do
    IFS='|' read -r name display delay fields <<< "$def"

    enabled="false"
    if jq -e --arg name "$name" '.[$name] == true' <<< "$ENABLED_CHANNELS" >/dev/null; then
        enabled="true"
    fi

    ch_json=$(jq -n --argjson enabled "$enabled" --argjson delay "$delay" '{enabled: $enabled, delay: $delay}')

    if [ "$name" = "macos" ]; then
        ch_json=$(echo "$ch_json" | jq '. + {sound: "Glass", events: ["notification"]}')
    fi

    if [ -n "$fields" ]; then
        IFS=';' read -ra FIELD_DEFS <<< "$fields"
        for fdef in "${FIELD_DEFS[@]}"; do
            IFS=':' read -r fkey fdesc <<< "$fdef"
            val=$(jq -r --arg name "$name" --arg key "$fkey" '.[$name][$key] // empty' <<< "$CHANNEL_CONFIGS")

            if [ -z "$val" ] && [ -f "$CONFIG_FILE" ]; then
                val=$(jq -r ".channels.\"${name}\".\"${fkey}\" // empty" "$CONFIG_FILE" 2>/dev/null) || true
            fi

            if [ -z "$val" ] && [[ "$fdesc" =~ \[(.+)\] ]]; then
                val="${BASH_REMATCH[1]}"
            fi

            if [ -n "$val" ]; then
                ch_json=$(echo "$ch_json" | jq --arg v "$val" --arg k "$fkey" '.[$k] = $v')
            fi
        done
    fi

    CONFIG_JSON=$(echo "$CONFIG_JSON" | jq --argjson ch "$ch_json" --arg name "$name" '.channels[$name] = $ch')
done

mkdir -p "$INSTALL_DIR"
echo "$CONFIG_JSON" | jq '.' > "$CONFIG_FILE"
echo -e "  ${GREEN}✓${NC} 配置已写入 $CONFIG_FILE"

# ============================================================
#  [3/4] 安装脚本
# ============================================================
echo -e "${YELLOW}[3/4]${NC} 安装脚本..."
mkdir -p "$STATE_DIR" "$SCRIPTS_DIR"
cp -R "$REPO_ROOT/scripts/." "$SCRIPTS_DIR/"
chmod +x \
    "$SCRIPTS_DIR/notify.sh" \
    "$SCRIPTS_DIR/clear_pending.sh" \
    "$SCRIPTS_DIR/pre_tool_use.sh" \
    "$SCRIPTS_DIR/channels/"*.sh
echo -e "  ${GREEN}✓${NC} 脚本已复制到 $SCRIPTS_DIR"

# ============================================================
#  [4/4] 写入 hooks.json
# ============================================================
echo -e "${YELLOW}[4/4]${NC} 写入 hooks.json..."

# 事件、matcher、参数和超时均来自插件定义；安装路径由 @sh 引用。
HOOKS_JSON=$(jq --arg scripts "$SCRIPTS_DIR" --arg config "$CONFIG_FILE" --arg state "$STATE_DIR" '
    (.hooks[][] | .hooks[] | select(.type == "command") | .command) |= (
        (capture("^(?:CC_NOTIFY_AGENT=codex )?bash \"\\$\\{PLUGIN_ROOT\\}/scripts/(?<script>notify\\.sh|clear_pending\\.sh|pre_tool_use\\.sh)\"(?<args>(?: .*)?)$")
            // error("无法转换 Codex hook 命令: " + .)) as $entry
        | "CC_NOTIFY_CONFIG=" + ($config | @sh)
            + " CC_NOTIFY_STATE_DIR=" + ($state | @sh)
            + " CC_NOTIFY_AGENT=codex bash " + (($scripts + "/" + $entry.script) | @sh)
            + $entry.args
    )
' "$REPO_ROOT/hooks/codex-hooks.json")

mkdir -p "$CODEX_HOME_DIR"
HOOKS_TMP=$(mktemp "${HOOKS_FILE}.tmp.XXXXXX")
trap 'rm -f "$HOOKS_TMP"' EXIT
if [ -f "$HOOKS_FILE" ]; then
    BACKUP=$(mktemp "${HOOKS_FILE}.backup.$(date +%Y%m%d%H%M%S).XXXXXX")
    cp "$HOOKS_FILE" "$BACKUP"
    echo "  已备份原 hooks.json 到: $BACKUP"

    # 仅移除调用本安装目录已知脚本的命令，保留同事件、同组中的其他 hook。
    jq --arg scripts "$SCRIPTS_DIR" --argjson incoming "$HOOKS_JSON" '
        def owned_hook:
            .type == "command" and (
                (.command // "") as $command
                | any(["notify.sh", "clear_pending.sh", "pre_tool_use.sh"][];
                    ($scripts + "/" + .) as $path
                    | any([$path, ($path | @sh), ("\"" + $path + "\"")][];
                        . as $token
                        | ($command == $token)
                            or ($command | startswith($token + " "))
                            or ($command == ("bash " + $token))
                            or ($command | startswith("bash " + $token + " "))
                            or ($command | endswith(" bash " + $token))
                            or ($command | contains(" bash " + $token + " "))
                    )
                )
            );
        .hooks = ((.hooks // {}) | with_entries(
            .value |= map(
                .hooks |= map(select(owned_hook | not))
                | select(.hooks | length > 0)
            )
        ))
        | reduce ($incoming.hooks | to_entries[]) as $event (.;
            .hooks[$event.key] = ((.hooks[$event.key] // []) + $event.value)
        )
    ' "$HOOKS_FILE" > "$HOOKS_TMP"
    mv "$HOOKS_TMP" "$HOOKS_FILE"
    echo -e "  ${GREEN}✓${NC} hooks 已合并到 $HOOKS_FILE"
else
    printf '%s\n' "$HOOKS_JSON" > "$HOOKS_TMP"
    mv "$HOOKS_TMP" "$HOOKS_FILE"
    echo -e "  ${GREEN}✓${NC} 已创建 $HOOKS_FILE"
fi
trap - EXIT

# ============================================================
#  总结输出
# ============================================================
echo ""
ENABLED_COUNT=$(jq 'length' <<< "$ENABLED_CHANNELS")

if [ "$ENABLED_COUNT" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} 未启用任何推送渠道"
else
    echo "  已启用的渠道："
    for def in "${CHANNEL_DEFS[@]}"; do
        IFS='|' read -r name display delay _ <<< "$def"
        if jq -e --arg name "$name" '.[$name] == true' <<< "$ENABLED_CHANNELS" >/dev/null; then
            echo -e "  ${GREEN}✓${NC} ${display} (延迟 ${delay}s)"
        fi
    done
fi

echo ""
echo "========================================="
echo -e "  ${GREEN}✅ 安装完成！${NC}"
echo ""

echo "  Codex 0.169.0 默认启用 hooks，功能开关为 [features].hooks。"
echo "  如曾显式关闭，请在 $CODEX_CONFIG 中将 hooks 改为 true。"
echo "  codex_hooks 是已弃用的别名，新配置请使用 hooks。"
echo ""
echo "  安装或升级后，启动 Codex 并运行 /hooks，审阅并信任本次安装的 hooks。"
echo "  调试: tail -f /tmp/claude-hooks-debug.log"
echo ""
echo "  修改配置: 编辑 $CONFIG_FILE"
echo "  状态目录: $STATE_DIR"
echo "========================================="
