#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_URL=${REPOSITORY_URL:-https://github.com/bimaidalao/dujiao-xboard-sso-bridge.git}
INSTALL_DIR=${INSTALL_DIR:-/opt/dujiao-xboard-sso-bridge}
BRANCH=${BRANCH:-main}

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
info() { printf '[INFO] %s\n' "$*"; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail '请使用 sudo 运行此安装命令'

if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    info '安装 git 和 curl'
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates
  else
    fail '服务器缺少 git/curl，且不是 apt 系统，请先手动安装'
  fi
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  if [[ -n "$(git -C "$INSTALL_DIR" status --porcelain)" ]]; then
    fail "$INSTALL_DIR 存在未提交修改。为避免覆盖，安装器已经停止。"
  fi
  info '更新已存在的项目目录'
  git -C "$INSTALL_DIR" fetch origin "$BRANCH"
  git -C "$INSTALL_DIR" switch "$BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
elif [[ -e "$INSTALL_DIR" ]]; then
  fail "$INSTALL_DIR 已存在但不是 Git 仓库，请更换 INSTALL_DIR 或先人工检查"
else
  info "下载项目到 $INSTALL_DIR"
  git clone --branch "$BRANCH" --depth 1 "$REPOSITORY_URL" "$INSTALL_DIR"
fi

info '启动统一安装命令'
exec bash "$INSTALL_DIR/bin/dx-bridge" install "$@" </dev/tty
