#!/usr/bin/env bash
#
# 一键安装脚本
# 将 hooks 脚本部署到 ~/.claude/hooks/ 并合并配置到 settings.json
# 兼容 macOS/Linux，兼容 cc-switch 和直接配置

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="${HOME}/.claude/hooks"
STATE_DIR="${HOOKS_DIR}/state"
SETTINGS_FILE="${HOME}/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

IS_MACOS=false
if [[ "$(uname -s)" == "Darwin" ]]; then
    IS_MACOS=true
fi

echo "========================================="
echo "  Claude Code 分级通知 - 安装"
echo "  平台: $(uname -s) $(uname -m)"
echo "========================================="
echo ""

# 1. 检查依赖
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
    echo "  请先安装缺失的依赖后重新运行："
    if $IS_MACOS; then
        echo "  macOS:         brew install jq curl"
    else
        echo "  Debian/Ubuntu: sudo apt install -y jq curl"
        echo "  CentOS/RHEL:   sudo yum install -y jq curl"
    fi
    exit 1
fi

# 2. 复制脚本
echo -e "${YELLOW}[2/4]${NC} 安装脚本..."
mkdir -p "$HOOKS_DIR" "$STATE_DIR"
cp "$SCRIPT_DIR/notify.sh" "$HOOKS_DIR/notify.sh"
cp "$SCRIPT_DIR/clear_pending.sh" "$HOOKS_DIR/clear_pending.sh"
chmod +x "$HOOKS_DIR/notify.sh" "$HOOKS_DIR/clear_pending.sh"
echo -e "  ${GREEN}✓${NC} 脚本已复制到 $HOOKS_DIR"

# macOS 提示
if $IS_MACOS; then
    echo -e "  ${GREEN}✓${NC} 检测到 macOS，将启用系统原生通知"
fi

# 3. 配置 hooks（区分 cc-switch 和直接配置）
echo -e "${YELLOW}[3/4]${NC} 配置 hooks..."

if command -v cc-switch &>/dev/null; then
    # cc-switch 模式：合并到 common config
    echo "  检测到 cc-switch，使用 common config 方式配置"

    # 读取现有 common config
    EXISTING=$(cc-switch config common show -a claude 2>/dev/null | sed -n '/^{/,/^}/p' || echo "{}")
    if [ -z "$EXISTING" ] || [ "$EXISTING" = "{}" ]; then
        EXISTING="{}"
    fi

    # 合并 hooks 到现有 common config
    HOOKS_JSON=$(cat "$SCRIPT_DIR/settings.json")
    MERGED=$(echo "$EXISTING" "$HOOKS_JSON" | jq -s '.[0] * {hooks: .[1].hooks}')

    TMP_MERGED=$(mktemp)
    echo "$MERGED" > "$TMP_MERGED"
    cc-switch config common set -a claude --file "$TMP_MERGED" --apply 2>/dev/null
    rm -f "$TMP_MERGED"

    echo -e "  ${GREEN}✓${NC} hooks 已合并到 cc-switch common config"
    echo -e "  ${GREEN}✓${NC} 已应用到当前配置"
else
    # 直接配置模式：合并到 settings.json
    if [ -f "$SETTINGS_FILE" ]; then
        BACKUP="${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$SETTINGS_FILE" "$BACKUP"
        echo "  已备份原配置到: $BACKUP"

        HOOKS_JSON=$(cat "$SCRIPT_DIR/settings.json")
        jq -s '.[0] * {hooks: .[1].hooks}' "$SETTINGS_FILE" <(echo "$HOOKS_JSON") \
            > "${SETTINGS_FILE}.tmp" \
            && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

        echo -e "  ${GREEN}✓${NC} hooks 已合并到 settings.json"
    else
        cp "$SCRIPT_DIR/settings.json" "$SETTINGS_FILE"
        echo -e "  ${GREEN}✓${NC} 已创建 settings.json"
    fi
fi

# 4. 检查环境变量
echo -e "${YELLOW}[4/4]${NC} 检查推送凭证..."
MISSING=0

if $IS_MACOS; then
    echo -e "  ${GREEN}✓${NC} macOS 系统通知（无需配置，开箱即用）"
fi

if [ -n "${BARK_KEY:-}" ]; then
    echo -e "  ${GREEN}✓${NC} BARK_KEY 已设置 (${BARK_KEY:0:6}...)"
else
    if $IS_MACOS; then
        echo -e "  ℹ️  BARK_KEY 未设置（macOS 已有系统通知，Bark 为可选远程备用）"
    else
        echo -e "  ${YELLOW}⚠${NC} BARK_KEY 未设置 - Bark 推送不可用"
        echo "     export BARK_KEY=\"your-bark-key\""
        MISSING=1
    fi
fi

if [ -n "${QYWX_WEBHOOK:-}" ]; then
    echo -e "  ${GREEN}✓${NC} QYWX_WEBHOOK 已设置"
else
    echo -e "  ${YELLOW}⚠${NC} QYWX_WEBHOOK 未设置 - 企业微信推送不可用"
    echo "     export QYWX_WEBHOOK=\"https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-key\""
    if ! $IS_MACOS; then
        MISSING=1
    fi
fi

if [ -z "${BARK_SERVER:-}" ]; then
    echo -e "  ℹ️  BARK_SERVER 未设置，将使用默认服务器 https://api.day.app"
fi

# cc-switch 用户提示
if command -v cc-switch &>/dev/null && [ -n "${BARK_KEY:-}" ]; then
    echo ""
    echo -e "  ${YELLOW}cc-switch 用户注意${NC}："
    echo "  hooks 的执行环境可能拿不到 ~/.bashrc 中的变量。"
    echo "  如果测试推送失败，请将凭证写入 cc-switch env："
    echo "    cc-switch env set BARK_KEY \"$BARK_KEY\" -a claude"
    [ -n "${QYWX_WEBHOOK:-}" ] && echo "    cc-switch env set QYWX_WEBHOOK \"$QYWX_WEBHOOK\" -a claude"
fi

echo ""
echo "========================================="
if $IS_MACOS; then
    echo -e "  ${GREEN}✅ 安装完成！${NC}（macOS 系统通知已就绪）"
elif [ "$MISSING" -eq 0 ]; then
    echo -e "  ${GREEN}✅ 安装完成！${NC}"
else
    echo -e "  ${GREEN}✅ 脚本已安装${NC}，请补充环境变量后即可使用"
fi
echo ""
echo "  下一步:"
echo "  1. 运行测试: bash $SCRIPT_DIR/test_notify.sh all"
echo "  2. 重启 Claude Code 使 hooks 生效"
echo "  3. 调试日志: tail -f /tmp/claude-hooks-debug.log"
echo "========================================="
