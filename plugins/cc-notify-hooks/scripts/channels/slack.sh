#!/usr/bin/env bash
# Slack Incoming Webhook

send_slack() {
    local title="$1" body="$2" config="$3" event_json="${4:-}"
    local webhook format
    webhook=$(echo "$config" | jq -r '.webhook')
    format=$(echo "$config" | jq -r '.format // "markdown"')

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/notify_format.sh"

    if [ "$format" = "text" ] || ! notify_has_event_json "$event_json"; then
        curl -sf --max-time 10 \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg text "*$title*
$body" \
                '{text:$text}')" \
            "$webhook" >/dev/null 2>&1 || true
        return 0
    fi

    local text
    text=$(notify_long_markdown "$event_json" | sed 's/\*\*/\*/g')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg title "$title" \
            --arg text "$text" \
            '{
                text: ($title + "\n" + $text),
                blocks: [
                    {type:"section", text:{type:"mrkdwn", text:("*" + $title + "*")}},
                    {type:"section", text:{type:"mrkdwn", text:$text}}
                ]
            }')" \
        "$webhook" >/dev/null 2>&1 || true
}
