#!/usr/bin/env bash
#
# 一键安装脚本
# 交互式配置 → 部署脚本 → 合并 hooks 到 settings.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${HOME}/.claude/hooks"
STATE_DIR="${HOOKS_DIR}/state"
CONFIG_FILE="${HOOKS_DIR}/notify.conf"
SETTINGS_FILE="${HOME}/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

echo "========================================="
echo "  Claude Code 分级通知 - 安装"
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
echo -e "${YELLOW}[2/4]${NC} 配置推送参数..."
echo ""

# 读取已有配置（配置文件 > 环境变量 > 默认值）
_read_conf() {
    local key="$1" default="$2"
    if [ -f "$CONFIG_FILE" ]; then
        local val
        val=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^[^=]*=//;s/^"//;s/"$//') || true
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
}

D_BARK_KEY=$(_read_conf BARK_KEY "${BARK_KEY:-}")
D_BARK_SERVER=$(_read_conf BARK_SERVER "${BARK_SERVER:-https://api.day.app}")
D_QYWX_WEBHOOK=$(_read_conf QYWX_WEBHOOK "${QYWX_WEBHOOK:-}")
D_BARK_DELAY=$(_read_conf BARK_DELAY "${BARK_DELAY:-15}")
D_WECHAT_DELAY=$(_read_conf WECHAT_DELAY "${WECHAT_DELAY:-300}")

if [ -f "$CONFIG_FILE" ]; then
    echo -e "  ${CYAN}检测到已有配置，当前值作为默认${NC}"
fi
echo -e "  ${CYAN}直接回车使用 [...] 中的值${NC}"
echo ""

# --- Bark Key ---
if [ -n "$D_BARK_KEY" ]; then
    BARK_HINT="${D_BARK_KEY:0:8}..."
else
    BARK_HINT="可选，回车跳过"
fi
read -rp "  Bark Key [$BARK_HINT]: " input
BARK_KEY="${input:-$D_BARK_KEY}"

# --- Bark Server ---
read -rp "  Bark Server [$D_BARK_SERVER]: " input
BARK_SERVER="${input:-$D_BARK_SERVER}"

# --- 企业微信 ---
if [ -n "$D_QYWX_WEBHOOK" ]; then
    QYWX_HINT="已设置"
else
    QYWX_HINT="可选，回车跳过"
fi
read -rp "  企业微信 Webhook [$QYWX_HINT]: " input
QYWX_WEBHOOK="${input:-$D_QYWX_WEBHOOK}"

# --- 延迟 ---
read -rp "  Bark 推送延迟/秒 [$D_BARK_DELAY]: " input
BARK_DELAY="${input:-$D_BARK_DELAY}"

read -rp "  企业微信推送延迟/秒 [$D_WECHAT_DELAY]: " input
WECHAT_DELAY="${input:-$D_WECHAT_DELAY}"

echo ""

# 写入配置文件
mkdir -p "$HOOKS_DIR"
cat > "$CONFIG_FILE" << EOF
# Claude Code 通知推送配置（由 install.sh 生成，可手动编辑）
BARK_KEY="${BARK_KEY}"
BARK_SERVER="${BARK_SERVER}"
QYWX_WEBHOOK="${QYWX_WEBHOOK}"
BARK_DELAY=${BARK_DELAY}
WECHAT_DELAY=${WECHAT_DELAY}
MACOS_DELAY=3
RATE_LIMIT=10
EOF

echo -e "  ${GREEN}✓${NC} 配置已写入 $CONFIG_FILE"

# ============================================================
#  [3/4] 安装脚本
# ============================================================
echo -e "${YELLOW}[3/4]${NC} 安装脚本..."
mkdir -p "$STATE_DIR"
cp "$SCRIPT_DIR/notify.sh" "$HOOKS_DIR/notify.sh"
cp "$SCRIPT_DIR/clear_pending.sh" "$HOOKS_DIR/clear_pending.sh"
chmod +x "$HOOKS_DIR/notify.sh" "$HOOKS_DIR/clear_pending.sh"
echo -e "  ${GREEN}✓${NC} 脚本已复制到 $HOOKS_DIR"

if $IS_MACOS; then
    echo -e "  ${GREEN}✓${NC} macOS 系统通知已启用（Notification 事件，延迟 3s）"
fi

# ============================================================
#  [4/4] 配置 hooks
# ============================================================
echo -e "${YELLOW}[4/4]${NC} 配置 hooks..."
HOOKS_JSON=$(cat "$SCRIPT_DIR/settings.json")

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
WARN=0
if [ -z "$BARK_KEY" ] && [ -z "$QYWX_WEBHOOK" ]; then
    if $IS_MACOS; then
        echo -e "  ${GREEN}✓${NC} macOS 系统通知可用"
        echo -e "  ℹ️  未配置远程推送，仅本地通知"
    else
        echo -e "  ${YELLOW}⚠${NC} 未配置任何推送渠道"
        WARN=1
    fi
else
    [ -n "$BARK_KEY" ] && echo -e "  ${GREEN}✓${NC} Bark 推送已配置"
    [ -n "$QYWX_WEBHOOK" ] && echo -e "  ${GREEN}✓${NC} 企业微信推送已配置"
    $IS_MACOS && echo -e "  ${GREEN}✓${NC} macOS 系统通知已启用"
fi

echo ""
echo "========================================="
if [ "$WARN" -eq 0 ]; then
    echo -e "  ${GREEN}✅ 安装完成！${NC}"
else
    echo -e "  ${GREEN}✅ 脚本已安装${NC}，请补充推送配置"
fi
echo ""
echo "  下一步:"
echo "  1. 运行测试: bash $SCRIPT_DIR/test_notify.sh all"
echo "  2. 重启 Claude Code 使 hooks 生效"
echo "  3. 调试日志: tail -f /tmp/claude-hooks-debug.log"
echo ""
echo "  修改配置: 编辑 $CONFIG_FILE"
echo "========================================="
