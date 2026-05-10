#!/usr/bin/env bash
#
# cc-notify-hooks 独立安装入口（路由）
#
# 用法：
#   bash install.sh           # 交互式选择目标
#   bash install.sh claude    # 直接安装 Claude Code 分支
#   bash install.sh codex     # 直接安装 Codex CLI 分支
#
# 或绕过路由直接调用子脚本：
#   bash install/claude.sh
#   bash install/codex.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
#  解析参数 / 交互式选择
# ============================================================
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
    echo "========================================="
    echo "  cc-notify-hooks - 独立安装"
    echo "========================================="
    echo ""
    echo "  请选择要安装到哪个工具："
    echo ""
    echo "    1) Claude Code  (~/.claude/)"
    echo "    2) Codex CLI    (~/.codex/)"
    echo ""
    printf "  选择 [1/2]: "
    read -r choice

    case "$choice" in
        1) TARGET="claude" ;;
        2) TARGET="codex" ;;
        *) echo -e "  ${YELLOW}无效选择，退出${NC}" ; exit 1 ;;
    esac
    echo ""
fi

# ============================================================
#  分发到子脚本
# ============================================================
case "$TARGET" in
    claude|claude-code|cc)
        echo -e "${CYAN}→ 进入 Claude Code 分支${NC}"
        echo ""
        exec bash "$REPO_ROOT/install/claude.sh"
        ;;
    codex)
        echo -e "${CYAN}→ 进入 Codex CLI 分支${NC}"
        echo ""
        exec bash "$REPO_ROOT/install/codex.sh"
        ;;
    *)
        echo "  未知目标: $TARGET"
        echo "  支持的目标: claude, codex"
        exit 1
        ;;
esac
