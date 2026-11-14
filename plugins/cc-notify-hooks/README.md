# cc-notify-hooks

cc-notify-hooks sends tiered notifications when your coding agent needs a reply,
requests permission, finishes a task, or reports a supported failure event.
Configure a short delay for desktop or phone notifications and a longer delay
for team messaging. Further interaction cancels pending notifications for the
same session. Other sessions keep their own queues.

The plugin runs local Bash scripts and requires `jq` and `curl`. macOS desktop
notifications also use `osascript`. Supported channels are macOS, Bark,
Telegram, Pushover, ntfy, Gotify, WeCom, Feishu, DingTalk, Slack, and Discord.
Without a configuration file, macOS receives system notifications for events
requiring attention; other systems send nothing.

## Installation and configuration

Use the agent-specific installation instructions in the
[repository README](https://github.com/MarioZZJ/cc-notify-hooks#安装).
On Claude Code 2.1.275 or later, register the marketplace and install with:

```text
/plugin install cc-notify-hooks --marketplace MarioZZJ/cc-notify-hooks
```

The actual plugin directory is `plugins/cc-notify-hooks`.
Claude Code loads `hooks/hooks.json`; Codex uses the explicit
`hooks/codex-hooks.json` declaration in `.codex-plugin/plugin.json`.

DeepSeek Harness installs this directory as the **`dsh-notify-hooks`** package.
Its `package.json` declares `dsh-plugin/cordis.patch.yml`; the bundle includes
the native event module and shared notification scripts. From the repository
root, run `bash install.sh dsh web` (or `desktop` for the desktop profile).
Remove a profile installation with
`dsh plugin --profile <profile> remove dsh-notify-hooks`.

In Claude Code, run `/cc-notify-hooks:config`. Codex can invoke the bundled
`config` skill. dsh and Magpie use the configuration files created by their
installers; `config/notify.example.json` supplies a manual setup template.
`CC_NOTIFY_CONFIG` selects an explicit
configuration file. Store credentials in the user's configuration or plugin
data directory, outside the installed plugin bundle.

Codex requires review and trust of installed hooks. Use `/hooks` in the CLI
or **Settings > Hooks** on desktop, including after bundled scripts change.

## Data and execution

`scripts/notify.sh` receives event JSON through standard input, filters events,
builds a notification, and starts a delayed local sender. It calls only the
channels enabled in your configuration. `scripts/pre_tool_use.sh` routes
supported structured questions. `scripts/clear_pending.sh` cancels queued
notifications for the current session.

Notifications can contain the agent name, project, event type, a short message
or first question, tool name, model, working directory, hostname, and session
identifier. Rich messages can also include the first question's option labels.
Enabled network channels send that information to their configured service or
webhook. The macOS channel displays it locally. Channel credentials authenticate
requests to the chosen provider.

The script currently appends incoming hook payloads to
`/tmp/claude-hooks-debug.log`; payloads can contain prompts and tool arguments.
Pending markers and rate-limit records are stored in the plugin's state
directory. Consult the repository README for configuration locations, event
coverage, cancellation timing, and uninstall instructions.

## License and support

MIT License. Report problems through the
[issue tracker](https://github.com/MarioZZJ/cc-notify-hooks/issues).
