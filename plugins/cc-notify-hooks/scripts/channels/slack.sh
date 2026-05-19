#!/usr/bin/env bash
# Slack Incoming Webhook

send_slack() {
    local title="$1" body="$2" config="$3"
    local webhook
    webhook=$(echo "$config" | jq -r '.webhook')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg text "*$title*
$body" \
            '{text:$text}')" \
        "$webhook" >/dev/null 2>&1 || true
}
