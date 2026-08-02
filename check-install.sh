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
check '商城订单工单控制器已安装' test -f "${XBOARD_DIR:-/opt/xboard}/app/Http/Controllers/V1/User/StoreOrderTicketController.php"
check '双系统最近订单逻辑已安装' grep -Fq 'appendNodeOrderSummary' "${XBOARD_DIR:-/opt/xboard}/app/Http/Controllers/V1/User/StoreOrderTicketController.php"
check '安装状态文件存在' test -r /var/lib/dujiao-xboard-sso-bridge/state.env

if [[ -n "$STORE_DOMAIN" ]]; then
  check '商城首页可访问' curl -fsSI --max-time 15 "https://$STORE_DOMAIN/"
  if [[ -n "$PANEL_DOMAIN" ]]; then
    check '商城订单安全接口已安装' sh -c "test \"\$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -X OPTIONS -H 'Origin: https://${PANEL_DOMAIN}' 'https://${STORE_DOMAIN}/sso/orders')\" = 204"
  else
    printf '[SKIP] 未设置 PANEL_DOMAIN，跳过商城订单接口 CORS 检查\n'
  fi
else
  printf '[SKIP] 未设置 STORE_DOMAIN，跳过商城 HTTP 检查\n'
fi

if [[ -n "$PANEL_DOMAIN" ]]; then
  check '节点首页可访问' curl -fsSI --max-time 15 "https://$PANEL_DOMAIN/"
else
  printf '[SKIP] 未设置 PANEL_DOMAIN，跳过节点 HTTP 检查\n'
fi

exit "$failed"
