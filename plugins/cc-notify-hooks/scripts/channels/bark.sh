#!/usr/bin/env bash
# Bark 推送（iOS/macOS/Android）

send_bark() {
    local title="$1" body="$2" config="$3"
    local key server sound
    key=$(echo "$config" | jq -r '.key')
    server=$(echo "$config" | jq -r '.server // "https://api.day.app"')
    sound=$(echo "$config" | jq -r '.sound // empty')

    local payload
    payload=$(jq -n \
        --arg key "$key" \
        --arg title "$title" \
        --arg body "$body" \
        '{device_key:$key, title:$title, body:$body, level:"timeSensitive", group:"claude-code"}')

    if [[ -n "$sound" ]]; then
        payload=$(echo "$payload" | jq --arg sound "$sound" '. + {sound:$sound}')
    fi

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${server}/push" >/dev/null 2>&1 || true
}
