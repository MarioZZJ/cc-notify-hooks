#!/usr/bin/env bash
# 飞书群机器人 Webhook

send_feishu() {
    local title="$1" body="$2" config="$3"
    local webhook
    webhook=$(echo "$config" | jq -r '.webhook')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg text "$title
$body" \
            '{msg_type:"text", content:{text:$text}}')" \
        "$webhook" >/dev/null 2>&1 || true
}
