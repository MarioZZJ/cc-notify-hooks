#!/usr/bin/env bash
# 飞书群机器人 Webhook

send_feishu() {
    local title="$1" body="$2" config="$3" event_json="${4:-}"
    local webhook format
    webhook=$(echo "$config" | jq -r '.webhook')
    format=$(echo "$config" | jq -r '.format // "card"')

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/../lib/notify_format.sh"

    if [ "$format" = "text" ] || ! notify_has_event_json "$event_json"; then
        curl -sf --max-time 10 \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg text "$title
$body" \
                '{msg_type:"text", content:{text:$text}}')" \
            "$webhook" >/dev/null 2>&1 || true
        return 0
    fi

    local payload
    payload=$(printf '%s' "$event_json" | jq '
        def present: . != null and . != "";
        def field($label; $value): {
            is_short: true,
            text: {tag: "lark_md", content: ("**" + $label + "**\n" + $value)}
        };
        {
            msg_type: "interactive",
            card: {
                config: {wide_screen_mode: true},
                header: {
                    template: (.status_color // "blue"),
                    title: {tag: "plain_text", content: .title}
                },
                elements: [
                    {
                        tag: "div",
                        text: {tag: "lark_md", content: (.summary_short // "")}
                    },
                    {
                        tag: "div",
                        fields: (
                            [
                                field("项目"; (.project // "unknown")),
                                field("事件"; (.event_name // "unknown"))
                            ]
                            + (if (.tool_name | present) then [field("工具"; .tool_name)] else [] end)
                            + (if (.session_short | present) then [field("Session"; .session_short)] else [] end)
                        )
                    },
                    {tag: "hr"},
                    {
                        tag: "note",
                        elements: [
                            {
                                tag: "plain_text",
                                content: ([.model, .cwd, .hostname] | map(select(. != null and . != "")) | join(" · "))
                            }
                        ]
                    }
                ]
            }
        }
    ')

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook" >/dev/null 2>&1 || true
}
