#!/usr/bin/env bash
# dsh 安装入口：保留旧 home 注册，或安装到指定 profile（默认 web）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$REPO_ROOT/install/native.sh" dsh "$@"
