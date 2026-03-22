#!/usr/bin/env bash
# Telegram Bot API

send_telegram() {
    local title="$1" body="$2" config="$3"
    local bot_token chat_id
    bot_token=$(echo "$config" | jq -r '.bot_token')
    chat_id=$(echo "$config" | jq -r '.chat_id')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$chat_id" \
            --arg text "$title
$body" \
            '{chat_id:$chat_id, text:$text}')" \
        "https://api.telegram.org/bot${bot_token}/sendMessage" >/dev/null 2>&1 || true
}
