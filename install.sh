#!/usr/bin/env bash
#
# 一键安装脚本（非插件模式）
# 交互式配置 → 部署脚本 → 合并 hooks 到 settings.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${HOME}/.claude/hooks"
SCRIPTS_DIR="${HOOKS_DIR}/scripts"
STATE_DIR="${HOOKS_DIR}/state"
CONFIG_FILE="${HOOKS_DIR}/notify.json"
SETTINGS_FILE="${HOME}/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

echo "========================================="
echo "  cc-notify-hooks v2 - 安装"
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

# 读取已有配置
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

if [ -f "$CONFIG_FILE" ]; then
    echo -e "  ${CYAN}检测到已有配置 ($CONFIG_FILE)${NC}"
    echo ""
fi

# 旧配置迁移
if [ -f "${HOOKS_DIR}/notify.conf" ] && [ ! -f "$CONFIG_FILE" ]; then
    echo -e "  ${CYAN}检测到 v1 配置 (notify.conf)，将自动迁移${NC}"
    # 读取旧配置
    source "${HOOKS_DIR}/notify.conf"
    # 构建基础 JSON
    MIGRATE_JSON=$(jq -n \
        --arg bark_key "${BARK_KEY:-}" \
        --arg bark_server "${BARK_SERVER:-https://api.day.app}" \
        --arg qywx_webhook "${QYWX_WEBHOOK:-}" \
        --argjson bark_delay "${BARK_DELAY:-15}" \
        --argjson wechat_delay "${WECHAT_DELAY:-300}" \
        --argjson rate_limit "${RATE_LIMIT:-10}" \
        '{
            channels: {
                macos: {enabled: true, delay: 3, sound: "Glass", events: ["notification"]},
                bark: {enabled: ($bark_key != ""), delay: $bark_delay, key: $bark_key, server: $bark_server},
                wechat: {enabled: ($qywx_webhook != ""), delay: $wechat_delay, webhook: $qywx_webhook}
            },
            rate_limit: $rate_limit
        }')
    echo "$MIGRATE_JSON" > "$CONFIG_FILE"
    mv "${HOOKS_DIR}/notify.conf" "${HOOKS_DIR}/notify.conf.bak"
    echo -e "  ${GREEN}✓${NC} 已迁移，旧配置备份为 notify.conf.bak"
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
    # macOS 在 macOS 上默认启用
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

# 解析选择
declare -A ENABLED_CHANNELS
if [ -n "$selection" ]; then
    IFS=',' read -ra NUMS <<< "$selection"
    for num in "${NUMS[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#CHANNEL_DEFS[@]} ]; then
            IFS='|' read -r name _ _ _ <<< "${CHANNEL_DEFS[$((num - 1))]}"
            ENABLED_CHANNELS["$name"]=1
        fi
    done
else
    # 保持当前配置
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r name; do
            ENABLED_CHANNELS["$name"]=1
        done < <(jq -r '.channels // {} | to_entries[] | select(.value.enabled == true) | .key' "$CONFIG_FILE" 2>/dev/null)
    fi
    # macOS fallback
    if $IS_MACOS && [ ${#ENABLED_CHANNELS[@]} -eq 0 ]; then
        ENABLED_CHANNELS["macos"]=1
    fi
fi

echo ""

# 为每个启用的 channel 收集凭证
declare -A CHANNEL_CONFIGS

for def in "${CHANNEL_DEFS[@]}"; do
    IFS='|' read -r name display delay fields <<< "$def"

    if [ "${ENABLED_CHANNELS[$name]:-}" != "1" ]; then
        continue
    fi

    if [ -z "$fields" ]; then
        # 无凭证的 channel（macOS）
        continue
    fi

    echo -e "  ${CYAN}配置 ${display}:${NC}"

    IFS=';' read -ra FIELD_DEFS <<< "$fields"
    for fdef in "${FIELD_DEFS[@]}"; do
        IFS=':' read -r fkey fdesc <<< "$fdef"

        # 提取默认值提示
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
        CHANNEL_CONFIGS["${name}.${fkey}"]="${input:-$current}"
    done
    echo ""
done

# 构建 JSON 配置
CONFIG_JSON='{"channels":{},"rate_limit":10}'

# 读取已有 rate_limit
if [ -f "$CONFIG_FILE" ]; then
    old_rate=$(jq -r '.rate_limit // 10' "$CONFIG_FILE")
    CONFIG_JSON=$(echo "$CONFIG_JSON" | jq --argjson rl "$old_rate" '.rate_limit = $rl')
fi

for def in "${CHANNEL_DEFS[@]}"; do
    IFS='|' read -r name display delay fields <<< "$def"

    enabled="false"
    [ "${ENABLED_CHANNELS[$name]:-}" = "1" ] && enabled="true"

    # 构建 channel 对象
    ch_json=$(jq -n --argjson enabled "$enabled" --argjson delay "$delay" '{enabled: $enabled, delay: $delay}')

    # macOS 特殊字段
    if [ "$name" = "macos" ]; then
        ch_json=$(echo "$ch_json" | jq '. + {sound: "Glass", events: ["notification"]}')
    fi

    # 添加凭证字段
    if [ -n "$fields" ]; then
        IFS=';' read -ra FIELD_DEFS <<< "$fields"
        for fdef in "${FIELD_DEFS[@]}"; do
            IFS=':' read -r fkey fdesc <<< "$fdef"
            val="${CHANNEL_CONFIGS["${name}.${fkey}"]:-}"

            # 尝试从已有配置读取
            if [ -z "$val" ] && [ -f "$CONFIG_FILE" ]; then
                val=$(jq -r ".channels.\"${name}\".\"${fkey}\" // empty" "$CONFIG_FILE" 2>/dev/null) || true
            fi

            # 提取方括号中的默认值
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

# 写入配置文件
mkdir -p "$HOOKS_DIR"
echo "$CONFIG_JSON" | jq '.' > "$CONFIG_FILE"
echo -e "  ${GREEN}✓${NC} 配置已写入 $CONFIG_FILE"

# ============================================================
#  [3/4] 安装脚本
# ============================================================
echo -e "${YELLOW}[3/4]${NC} 安装脚本..."
mkdir -p "$STATE_DIR" "$SCRIPTS_DIR/channels"
cp "$SCRIPT_DIR/scripts/notify.sh" "$SCRIPTS_DIR/notify.sh"
cp "$SCRIPT_DIR/scripts/clear_pending.sh" "$SCRIPTS_DIR/clear_pending.sh"
cp "$SCRIPT_DIR/scripts/channels/"*.sh "$SCRIPTS_DIR/channels/"
chmod +x "$SCRIPTS_DIR/notify.sh" "$SCRIPTS_DIR/clear_pending.sh" "$SCRIPTS_DIR/channels/"*.sh
echo -e "  ${GREEN}✓${NC} 脚本已复制到 $SCRIPTS_DIR"

# ============================================================
#  [4/4] 配置 hooks
# ============================================================
echo -e "${YELLOW}[4/4]${NC} 配置 hooks..."

# 生成 hooks JSON，路径替换为实际安装路径
HOOKS_JSON=$(cat "$SCRIPT_DIR/hooks/hooks.json" | sed "s|\\\${CLAUDE_PLUGIN_ROOT}/scripts|${SCRIPTS_DIR}|g")

if [ -f "$SETTINGS_FILE" ]; then
    BACKUP="${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP"
    echo "  已备份原配置到: $BACKUP"

    jq -s '.[0] * {hooks: .[1].hooks}' "$SETTINGS_FILE" <(echo "$HOOKS_JSON") \
        > "${SETTINGS_FILE}.tmp" \
        && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

    echo -e "  ${GREEN}✓${NC} hooks 已合并到 settings.json"
else
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo "$HOOKS_JSON" > "$SETTINGS_FILE"
    echo -e "  ${GREEN}✓${NC} 已创建 settings.json"
fi

# ============================================================
#  验证
# ============================================================
echo ""
ENABLED_COUNT=0
for name in "${!ENABLED_CHANNELS[@]}"; do
    [ "${ENABLED_CHANNELS[$name]}" = "1" ] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
done

if [ "$ENABLED_COUNT" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} 未启用任何推送渠道"
else
    echo "  已启用的渠道："
    for def in "${CHANNEL_DEFS[@]}"; do
        IFS='|' read -r name display delay _ <<< "$def"
        if [ "${ENABLED_CHANNELS[$name]:-}" = "1" ]; then
            echo -e "  ${GREEN}✓${NC} ${display} (延迟 ${delay}s)"
        fi
    done
fi

echo ""
echo "========================================="
echo -e "  ${GREEN}✅ 安装完成！${NC}"
echo ""
echo "  下一步:"
echo "  1. 测试: bash $SCRIPT_DIR/test_notify.sh"
echo "  2. 重启 Claude Code 使 hooks 生效"
echo "  3. 调试: tail -f /tmp/claude-hooks-debug.log"
echo ""
echo "  修改配置: 编辑 $CONFIG_FILE"
echo "  插件模式: claude --plugin-dir $SCRIPT_DIR"
echo "========================================="
