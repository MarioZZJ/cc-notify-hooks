#!/usr/bin/env bash
# 钉钉群机器人 Webhook

send_dingtalk() {
    local title="$1" body="$2" config="$3"
    local webhook
    webhook=$(echo "$config" | jq -r '.webhook')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg content "$title
$body" \
            '{msgtype:"text", text:{content:$content}}')" \
        "$webhook" >/dev/null 2>&1 || true
}
