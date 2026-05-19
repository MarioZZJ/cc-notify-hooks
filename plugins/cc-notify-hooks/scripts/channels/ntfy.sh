#!/usr/bin/env bash
# ntfy 推送（开源自托管 / ntfy.sh）

send_ntfy() {
    local title="$1" body="$2" config="$3"
    local topic server
    topic=$(echo "$config" | jq -r '.topic')
    server=$(echo "$config" | jq -r '.server // "https://ntfy.sh"')

    curl -sf --max-time 10 \
        -H "Title: ${title}" \
        -H "Priority: 4" \
        -d "$body" \
        "${server}/${topic}" >/dev/null 2>&1 || true
}
