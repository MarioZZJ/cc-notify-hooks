#!/usr/bin/env bash
# Gotify 推送（自建服务）

send_gotify() {
    local title="$1" body="$2" config="$3"
    local server app_token
    server=$(echo "$config" | jq -r '.server')
    app_token=$(echo "$config" | jq -r '.app_token')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg title "$title" \
            --arg message "$body" \
            '{title:$title, message:$message, priority:5}')" \
        "${server}/message?token=${app_token}" >/dev/null 2>&1 || true
}
