#!/usr/bin/env bash
#
# 测试脚本 - 验证 Bark 和企业微信推送是否正常
#
# 用法：
#   ./test_notify.sh bark      # 仅测试 Bark
#   ./test_notify.sh wechat    # 仅测试企业微信
#   ./test_notify.sh all       # 测试全部
#   ./test_notify.sh hook      # 模拟完整 hook 流程（含延迟）

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 读取配置文件
_CONF="${HOME}/.claude/hooks/notify.conf"
if [ -f "$_CONF" ]; then
    # shellcheck source=/dev/null
    source "$_CONF"
fi

# 环境变量可覆盖配置文件
BARK_KEY="${BARK_KEY:-}"
BARK_SERVER="${BARK_SERVER:-https://api.day.app}"
QYWX_WEBHOOK="${QYWX_WEBHOOK:-}"

echo "========================================="
echo "  Claude Code 通知推送 - 连通性测试"
echo "========================================="
echo ""

test_bark() {
    echo -e "${YELLOW}[Bark]${NC} 测试推送..."

    if [ -z "$BARK_KEY" ]; then
        echo -e "${RED}[Bark]${NC} ❌ BARK_KEY 未设置"
        echo "       请在 shell 配置中添加: export BARK_KEY=\"your-key\""
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        echo -e "${RED}[Bark]${NC} ❌ jq 未安装"
        return 1
    fi

    echo -e "${YELLOW}[Bark]${NC} 服务器: ${BARK_SERVER}"
    echo -e "${YELLOW}[Bark]${NC} Key: ${BARK_KEY:0:6}..."

    # 使用 POST JSON 方式推送，与 notify.sh 保持一致
    RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg key "$BARK_KEY" \
            '{
                device_key: $key,
                title: "Claude Code Test",
                body: "Push notification is working!",
                level: "timeSensitive",
                group: "claude-code"
            }')" \
        "${BARK_SERVER}/push" \
        2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}[Bark]${NC} ✅ 推送成功！请检查你的 Mac 通知"
        echo "       响应: $BODY"
    else
        echo -e "${RED}[Bark]${NC} ❌ 推送失败"
        echo "       HTTP 状态码: $HTTP_CODE"
        echo "       响应内容: $BODY"
        echo ""
        echo "       排查步骤:"
        echo "       1. 确认代理生效: curl -I https://api.day.app"
        echo "       2. 确认 key 正确: echo \$BARK_KEY"
        echo "       3. 手动测试:"
        echo "          curl -v -H 'Content-Type: application/json' \\"
        echo "            -d '{\"device_key\":\"'\$BARK_KEY'\",\"title\":\"test\",\"body\":\"hello\"}' \\"
        echo "            ${BARK_SERVER}/push"
    fi
}

test_wechat() {
    echo -e "${YELLOW}[企业微信]${NC} 测试推送..."

    if [ -z "$QYWX_WEBHOOK" ]; then
        echo -e "${RED}[企业微信]${NC} ❌ QYWX_WEBHOOK 未设置"
        echo "       请在 shell 配置中添加: export QYWX_WEBHOOK=\"https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-key\""
        return 1
    fi

    echo -e "${YELLOW}[企业微信]${NC} Webhook: ${QYWX_WEBHOOK:0:60}..."

    RESPONSE=$(curl -s --max-time 10 -w "\n%{http_code}" \
        "$QYWX_WEBHOOK" \
        -H 'Content-Type: application/json' \
        -d '{"msgtype":"text","text":{"content":"Claude Code push notification test"}}' \
        2>&1)

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}[企业微信]${NC} ✅ 推送成功！请检查企业微信"
        echo "       响应: $BODY"
    else
        echo -e "${RED}[企业微信]${NC} ❌ 推送失败"
        echo "       HTTP 状态码: $HTTP_CODE"
        echo "       响应内容: $BODY"
        echo ""
        echo "       排查步骤:"
        echo "       1. 确认 webhook URL 完整（含 ?key= 部分）"
        echo "       2. 手动测试:"
        echo "          curl -v \"\$QYWX_WEBHOOK\" \\"
        echo "            -H 'Content-Type: application/json' \\"
        echo "            -d '{\"msgtype\":\"text\",\"text\":{\"content\":\"test\"}}'"
    fi
}

test_hook_flow() {
    echo -e "${YELLOW}[模拟 Hook]${NC} 模拟完整分级推送流程..."
    echo "  - ${BARK_DELAY:-15} 秒后发 Bark"
    echo "  - ${WECHAT_DELAY:-300} 秒后发企业微信（Ctrl+C 可中断）"
    echo ""

    MOCK_JSON='{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your response","cwd":"'"$PWD"'","session_id":"test-session"}'

    echo "$MOCK_JSON" | bash "$(dirname "$0")/notify.sh" idle

    echo -e "${GREEN}[模拟 Hook]${NC} ✅ 后台推送进程已启动"
    echo "  → 等待 ${BARK_DELAY:-15} 秒后检查 Bark 通知..."
    echo "  → 如需测试企业微信兜底，请等待 ${WECHAT_DELAY:-300} 秒"
    echo ""
    echo "  💡 模拟用户响应（取消推送）:"
    echo "     bash $(dirname "$0")/clear_pending.sh"
}

case "${1:-all}" in
    bark)
        test_bark
        ;;
    wechat|weixin)
        test_wechat
        ;;
    hook)
        test_hook_flow
        ;;
    all|*)
        test_bark
        echo ""
        test_wechat
        ;;
esac

echo ""
echo "========================================="
