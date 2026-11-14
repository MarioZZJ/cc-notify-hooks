#!/usr/bin/env bash
# dsh 复用已有 home 插件注册；新安装与 Magpie 使用各自的插件管理器。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?请指定 dsh 或 magpie}"
case "$TARGET" in
    dsh|magpie) ;;
    *) echo "支持的目标: dsh, magpie" >&2; exit 1 ;;
esac
for dependency in bash jq curl; do
    command -v "$dependency" >/dev/null 2>&1 || {
        echo "请先安装 $dependency" >&2
        exit 1
    }
done

if [ "$TARGET" = "dsh" ]; then
    DSH_HOME_DIR="${DSH_HOME:-${HOME}/.dsh}"
    PATCH_FILE="${DSH_HOME_DIR}/cordis.patch.yml"
    if [ -f "$PATCH_FILE" ] &&
       grep -Eq "^[[:space:]]*(-[[:space:]]*)?id:[[:space:]]*['\"]?cc-notify-hooks['\"]?([[:space:]]*(#.*)?)?$" "$PATCH_FILE"; then
        PLUGIN_LINK="${HOME}/node_modules/@dsh-local/dsh-cc-notify"
        mkdir -p "$(dirname "$PLUGIN_LINK")"
        ln -sfn "$REPO_ROOT/plugins/cc-notify-hooks/dsh-plugin" "$PLUGIN_LINK"
        echo "已更新 dsh-notify-hooks；保留旧安装的软链名称: $PLUGIN_LINK"
        echo "继续使用 $PATCH_FILE 中的 cc-notify-hooks 注册及其配置。"
        echo "已有通知配置和 stateDir 保持不变；本地安装引用本仓库，请保留该目录。"
        echo "重新启动对应 dsh 宿主以加载更新后的模块。"
        exit 0
    fi
    CONFIG_FILE="${CC_NOTIFY_CONFIG:-${DSH_HOME_DIR}/cc-notify-hooks/notify.json}"
else
    CONFIG_FILE="${CC_NOTIFY_CONFIG:-${HOME}/.config/cc-notify-hooks/notify.json}"
fi

command -v "$TARGET" >/dev/null 2>&1 || {
    echo "请先安装 $TARGET" >&2
    exit 1
}

if [ ! -f "$CONFIG_FILE" ]; then
    (umask 077
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cp "$REPO_ROOT/plugins/cc-notify-hooks/config/notify.example.json" "$CONFIG_FILE"
    )
fi

case "$TARGET" in
    dsh)
        PROFILE="${2:-web}"
        dsh plugin --profile "$PROFILE" add "$REPO_ROOT/plugins/cc-notify-hooks"
        echo "已注册 dsh-notify-hooks 到 $PROFILE；未启用 HMR 的 profile 请重新启动。"
        echo "桌面版使用: bash install.sh dsh desktop"
        ;;
    magpie)
        magpie plugin add "$REPO_ROOT"
        OPTIONS=$(jq -n --arg config "$CONFIG_FILE" '{configPath: $config, gatewayTimeoutMs: 3000}')
        magpie plugin options "$REPO_ROOT" "$OPTIONS"
        echo "已注册 Magpie 网关 hook 插件 agent-notify-hooks。"
        ;;
esac

echo "通知配置: $CONFIG_FILE"
echo "编辑配置以选择渠道、凭证和延迟；本地安装引用本仓库，请保留该目录。"
