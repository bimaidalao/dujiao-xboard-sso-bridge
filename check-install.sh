#!/usr/bin/env bash

set -u

STORE_DOMAIN=${STORE_DOMAIN:-}
PANEL_DOMAIN=${PANEL_DOMAIN:-}
failed=0

check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '[ OK ] %s\n' "$label"
  else
    printf '[FAIL] %s\n' "$label"
    failed=1
  fi
}

check '桥接服务正在运行' systemctl is-active --quiet dujiao-xboard-bridge.service
check '桥接仅监听本机端口' sh -c "ss -lnt | grep -q '127.0.0.1:18081'"
check 'Nginx 配置有效' nginx -t
check 'Xboard 控制器已安装' test -f "${XBOARD_DIR:-/opt/xboard}/app/Http/Controllers/V1/Passport/GoSsoController.php"

if [[ -n "$STORE_DOMAIN" ]]; then
  check '商城首页可访问' curl -fsSI --max-time 15 "https://$STORE_DOMAIN/"
else
  printf '[SKIP] 未设置 STORE_DOMAIN，跳过商城 HTTP 检查\n'
fi

if [[ -n "$PANEL_DOMAIN" ]]; then
  check '节点首页可访问' curl -fsSI --max-time 15 "https://$PANEL_DOMAIN/"
else
  printf '[SKIP] 未设置 PANEL_DOMAIN，跳过节点 HTTP 检查\n'
fi

exit "$failed"
