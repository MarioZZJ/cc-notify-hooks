#!/usr/bin/env bash
# Pushover 推送

send_pushover() {
    local title="$1" body="$2" config="$3"
    local app_token user_key
    app_token=$(echo "$config" | jq -r '.app_token')
    user_key=$(echo "$config" | jq -r '.user_key')

    curl -sf --max-time 10 \
        -d "token=${app_token}&user=${user_key}&title=${title}&message=${body}" \
        "https://api.pushover.net/1/messages.json" >/dev/null 2>&1 || true
}
