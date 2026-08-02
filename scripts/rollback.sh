#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_NAME=dujiao-xboard-sso-bridge
BACKUP_ROOT="/var/backups/$PROJECT_NAME"
ASSUME_YES=0
WITH_DB=0
BACKUP_DIR=''

while (($#)); do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --with-db) WITH_DB=1 ;;
    --backup) shift; BACKUP_DIR=${1:-} ;;
    *) printf '[FAIL] Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || { printf '[FAIL] Run as root\n' >&2; exit 1; }
if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r | head -n 1)
fi
[[ -d "$BACKUP_DIR" && -r "$BACKUP_DIR/paths.env" ]] || { printf '[FAIL] Invalid backup: %s\n' "$BACKUP_DIR" >&2; exit 1; }

# shellcheck disable=SC1090
source "$BACKUP_DIR/paths.env"
printf 'Backup: %s\nXboard: %s\nStore Nginx: %s\n' "$BACKUP_DIR" "$XBOARD_DIR" "$STORE_NGINX_CONF"
if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p 'Type ROLLBACK to continue: ' confirmation
  [[ "$confirmation" == ROLLBACK ]] || exit 1
fi

restore() { local backup=$1 target=$2; [[ -e "$BACKUP_DIR/$backup" ]] && cp -a "$BACKUP_DIR/$backup" "$target"; }
restore xboard.env "$XBOARD_DIR/.env"
restore xboard-route.php "$XBOARD_ROUTE_FILE"
restore xboard-user-route.php "$XBOARD_USER_ROUTE_FILE"
restore GoSsoController.php "$XBOARD_DIR/app/Http/Controllers/V1/Passport/GoSsoController.php"
restore StoreOrderTicketController.php "$XBOARD_DIR/app/Http/Controllers/V1/User/StoreOrderTicketController.php"
restore store-nginx.conf "$STORE_NGINX_CONF"
restore systemd-service /etc/systemd/system/dujiao-xboard-bridge.service
restore bridge.env /etc/dujiao-xboard-sso-bridge.env
[[ -n ${DUJIAO_LAYOUT_FILE:-} ]] && restore dujiao-layout "$DUJIAO_LAYOUT_FILE"
[[ -n ${XBOARD_LAYOUT_FILE:-} ]] && restore xboard-layout "$XBOARD_LAYOUT_FILE"
if [[ $WITH_DB -eq 1 && -e "$BACKUP_DIR/dujiao.db" ]]; then
  cp -a "$BACKUP_DIR/dujiao.db" "$DUJIAO_DB"
fi

systemctl daemon-reload
systemctl restart dujiao-xboard-bridge.service
nginx -t
systemctl reload nginx
if [[ -n ${XBOARD_DOCKER_CONTAINER:-} ]]; then
  docker exec -w "$XBOARD_CONTAINER_DIR" "$XBOARD_DOCKER_CONTAINER" php artisan optimize:clear >/dev/null
else
  php "$XBOARD_DIR/artisan" optimize:clear >/dev/null
fi
printf '[ OK ] Restored %s\n' "$BACKUP_DIR"
