#!/usr/bin/env bash
# Discord Webhook

send_discord() {
    local title="$1" body="$2" config="$3" event_json="${4:-}"
    local webhook format
    webhook=$(echo "$config" | jq -r '.webhook')
    format=$(echo "$config" | jq -r '.format // "embed"')

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/notify_format.sh"

    if [ "$format" = "text" ] || ! notify_has_event_json "$event_json"; then
        curl -sf --max-time 10 \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg content "**$title**
$body" \
                '{content:$content}')" \
            "$webhook" >/dev/null 2>&1 || true
        return 0
    fi

    local payload
    payload=$(printf '%s' "$event_json" | jq --argjson color "$(notify_color_decimal "$(printf '%s' "$event_json" | jq -r '.status_color // "blue"')" )" '
        def present: . != null and . != "";
        {
            embeds: [
                {
                    title: .title,
                    description: (.summary_short // ""),
                    color: $color,
                    fields: (
                        [
                            {name:"项目", value:(.project // "unknown"), inline:true},
                            {name:"事件", value:(.event_name // "unknown"), inline:true}
                        ]
                        + (if (.tool_name | present) then [{name:"工具", value:.tool_name, inline:true}] else [] end)
                        + (if (.session_short | present) then [{name:"Session", value:.session_short, inline:true}] else [] end)
                    ),
                    footer: {
                        text: ([.model, .cwd, .hostname] | map(select(. != null and . != "")) | join(" · "))
                    }
                }
            ]
        }
    ')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook" >/dev/null 2>&1 || true
}
