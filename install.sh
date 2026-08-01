#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_NAME='dujiao-xboard-sso-bridge'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=''
ASSUME_YES=0
DRY_RUN=0

log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  sudo bash install.sh
  sudo bash install.sh --config /path/to/install.env --yes

Options:
  --config FILE  Read deployment values from FILE.
  --yes          Skip the final confirmation (all values must be configured).
  --dry-run      Detect and validate only; do not change files or services.
  --help         Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --config) [[ $# -ge 2 ]] || die '--config needs a file'; CONFIG_FILE=$2; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Run this installer as root: sudo bash install.sh'
[[ -f "$SCRIPT_DIR/dujiao/public/index.php" ]] || die "Run install.sh from a complete $PROJECT_NAME checkout"

if [[ -n "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
for command_name in awk cp curl find grep install nginx php sed systemctl; do
  require_command "$command_name"
done

prompt_value() {
  local variable=$1 label=$2 default=${3:-} value=''
  value=${!variable:-}
  if [[ -z "$value" && $ASSUME_YES -eq 0 ]]; then
    if [[ -n "$default" ]]; then
      read -r -p "$label [$default]: " value
      value=${value:-$default}
    else
      read -r -p "$label: " value
    fi
  fi
  [[ -n "$value" ]] || die "$label is required"
  printf -v "$variable" '%s' "$value"
}

prompt_optional() {
  local variable=$1 label=$2 default=${3:-} value=${!1:-}
  if [[ -z "$value" && $ASSUME_YES -eq 0 ]]; then
    read -r -p "$label${default:+ [$default]} (留空跳过): " value
    value=${value:-$default}
  fi
  printf -v "$variable" '%s' "$value"
}

first_match() {
  find "$@" 2>/dev/null | head -n 1 || true
}

log '检测常见安装路径'
XBOARD_DIR=${XBOARD_DIR:-}
if [[ -z "$XBOARD_DIR" ]]; then
  artisan_path=$(first_match /www /opt /var/www -maxdepth 6 -type f -name artisan)
  [[ -n "$artisan_path" ]] && XBOARD_DIR=$(dirname "$artisan_path")
fi
prompt_value XBOARD_DIR 'Xboard 根目录' "${XBOARD_DIR:-/opt/xboard}"

DUJIAO_DB=${DUJIAO_DB:-}
if [[ -z "$DUJIAO_DB" ]]; then
  DUJIAO_DB=$(first_match /www /opt /var/www -type f -name dujiao.db)
fi
prompt_value DUJIAO_DB 'Dujiao SQLite 数据库路径' "${DUJIAO_DB:-/opt/dujiao-next/db/dujiao.db}"

DUJIAO_CONFIG=${DUJIAO_CONFIG:-}
if [[ -z "$DUJIAO_CONFIG" ]]; then
  DUJIAO_CONFIG=$(first_match "$(dirname "$(dirname "$DUJIAO_DB")")" -maxdepth 3 -type f -name config.yml)
fi
prompt_value DUJIAO_CONFIG 'Dujiao config.yml 路径' "${DUJIAO_CONFIG:-/opt/dujiao-next/config.yml}"

prompt_value STORE_DOMAIN 'AI 商城域名（不要写 https://）' "${STORE_DOMAIN:-store.example.com}"
prompt_value PANEL_DOMAIN '节点网站域名（不要写 https://）' "${PANEL_DOMAIN:-panel.example.com}"
prompt_value TELEGRAM_URL 'Telegram 客服链接' "${TELEGRAM_URL:-https://t.me/example}"
prompt_value TELEGRAM_HANDLE 'Telegram 客服用户名' "${TELEGRAM_HANDLE:-@example}"

[[ "$STORE_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die '商城域名格式不正确'
[[ "$PANEL_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die '节点域名格式不正确'
[[ "$STORE_DOMAIN" != *example.com ]] || die '请把示例商城域名改成真实域名'
[[ "$PANEL_DOMAIN" != *example.com ]] || die '请把示例节点域名改成真实域名'
[[ "$TELEGRAM_URL" == https://t.me/* ]] || die 'Telegram 客服链接必须以 https://t.me/ 开头'

XBOARD_ROUTE_FILE=${XBOARD_ROUTE_FILE:-$XBOARD_DIR/app/Http/Routes/V1/PassportRoute.php}
prompt_value XBOARD_ROUTE_FILE 'Xboard API 路由文件' "$XBOARD_ROUTE_FILE"

XBOARD_DOCKER_CONTAINER=${XBOARD_DOCKER_CONTAINER:-}
XBOARD_CONTAINER_DIR=${XBOARD_CONTAINER_DIR:-}
if [[ -z "$XBOARD_DOCKER_CONTAINER" ]] && command -v docker >/dev/null 2>&1; then
  while IFS= read -r container_name; do
    mount_template="{{range .Mounts}}{{if eq .Source \"$XBOARD_DIR\"}}{{.Destination}}{{end}}{{end}}"
    mount_destination=$(docker inspect --format "$mount_template" "$container_name" 2>/dev/null || true)
    if [[ -n "$mount_destination" ]]; then
      XBOARD_DOCKER_CONTAINER=$container_name
      XBOARD_CONTAINER_DIR=$mount_destination
      [[ "$container_name" == *web* ]] && break
    fi
  done < <(docker ps --format '{{.Names}}' 2>/dev/null)
fi
prompt_optional XBOARD_DOCKER_CONTAINER 'Xboard Web Docker 容器名' "$XBOARD_DOCKER_CONTAINER"
if [[ -n "$XBOARD_DOCKER_CONTAINER" ]]; then
  prompt_value XBOARD_CONTAINER_DIR 'Xboard 在容器内的目录' "${XBOARD_CONTAINER_DIR:-/www}"
fi

if [[ -z ${STORE_NGINX_CONF:-} ]]; then
  STORE_NGINX_CONF=$(grep -RIl --include='*.conf' "server_name.*${STORE_DOMAIN}" /etc/nginx /www/server/panel/vhost/nginx 2>/dev/null | head -n 1 || true)
fi
prompt_value STORE_NGINX_CONF '商城 Nginx 配置文件' "${STORE_NGINX_CONF:-/etc/nginx/sites-available/$STORE_DOMAIN.conf}"

default_user=$(stat -c '%U' "$DUJIAO_DB" 2>/dev/null || true)
[[ -n "$default_user" && "$default_user" != root ]] || default_user=www-data
prompt_value SERVICE_USER '桥接服务 Linux 用户' "${SERVICE_USER:-$default_user}"
prompt_value SERVICE_GROUP '桥接服务 Linux 用户组' "${SERVICE_GROUP:-$SERVICE_USER}"

DUJIAO_PUBLIC_DIR=${DUJIAO_PUBLIC_DIR:-}
DUJIAO_LAYOUT_FILE=${DUJIAO_LAYOUT_FILE:-}
XBOARD_PUBLIC_DIR=${XBOARD_PUBLIC_DIR:-}
XBOARD_LAYOUT_FILE=${XBOARD_LAYOUT_FILE:-}
dujiao_root_guess=$(dirname "$(dirname "$(dirname "$DUJIAO_DB")")")
if [[ -z "$DUJIAO_PUBLIC_DIR" && -d "$dujiao_root_guess/user/dist" ]]; then
  DUJIAO_PUBLIC_DIR="$dujiao_root_guess/user/dist"
fi
if [[ -z "$DUJIAO_LAYOUT_FILE" && -n "$DUJIAO_PUBLIC_DIR" && -f "$DUJIAO_PUBLIC_DIR/index.html" ]]; then
  DUJIAO_LAYOUT_FILE="$DUJIAO_PUBLIC_DIR/index.html"
fi
if [[ -z "$XBOARD_PUBLIC_DIR" && -d "$XBOARD_DIR/public" ]]; then
  XBOARD_PUBLIC_DIR="$XBOARD_DIR/public"
fi
if [[ -z "$XBOARD_LAYOUT_FILE" && -n "$XBOARD_PUBLIC_DIR" && -f "$XBOARD_PUBLIC_DIR/index.html" ]]; then
  XBOARD_LAYOUT_FILE="$XBOARD_PUBLIC_DIR/index.html"
fi
prompt_optional DUJIAO_PUBLIC_DIR 'Dujiao 静态资源根目录' "$DUJIAO_PUBLIC_DIR"
prompt_optional DUJIAO_LAYOUT_FILE 'Dujiao 全局 HTML/布局文件' "$DUJIAO_LAYOUT_FILE"
prompt_optional XBOARD_PUBLIC_DIR 'Xboard 静态资源根目录' "$XBOARD_PUBLIC_DIR"
prompt_optional XBOARD_LAYOUT_FILE 'Xboard 全局 HTML/布局文件' "$XBOARD_LAYOUT_FILE"

DUJIAO_IDENTITY_URL=${DUJIAO_IDENTITY_URL:-http://127.0.0.1:18080/api/v1/me}
XBOARD_USER_INFO_URL=${XBOARD_USER_INFO_URL:-http://127.0.0.1:7001/api/v1/user/info}
BRIDGE_LISTEN=${BRIDGE_LISTEN:-127.0.0.1:18081}

[[ -f "$XBOARD_DIR/artisan" ]] || die "Xboard artisan not found: $XBOARD_DIR/artisan"
[[ -f "$XBOARD_DIR/.env" ]] || die "Xboard .env not found: $XBOARD_DIR/.env"
[[ -d "$XBOARD_DIR/app/Http/Controllers/V1/Passport" ]] || die 'Xboard Passport controller directory not found; this version needs manual adaptation'
[[ -f "$XBOARD_ROUTE_FILE" ]] || die "Xboard route file not found: $XBOARD_ROUTE_FILE"
[[ -f "$DUJIAO_DB" ]] || die "Dujiao database not found: $DUJIAO_DB"
[[ -f "$DUJIAO_CONFIG" ]] || die "Dujiao config not found: $DUJIAO_CONFIG"
[[ -f "$STORE_NGINX_CONF" ]] || die "Nginx config not found: $STORE_NGINX_CONF"
id "$SERVICE_USER" >/dev/null 2>&1 || die "Linux user not found: $SERVICE_USER"
getent group "$SERVICE_GROUP" >/dev/null 2>&1 || die "Linux group not found: $SERVICE_GROUP"
if [[ -n "$XBOARD_DOCKER_CONTAINER" ]]; then
  command -v docker >/dev/null 2>&1 || die '配置了 Xboard Docker 容器，但服务器没有 docker 命令'
  docker inspect "$XBOARD_DOCKER_CONTAINER" >/dev/null 2>&1 || die "Docker container not found: $XBOARD_DOCKER_CONTAINER"
fi

if ! grep -F "$STORE_DOMAIN" "$STORE_NGINX_CONF" | grep -q 'server_name'; then
  die "The selected Nginx file does not contain server_name $STORE_DOMAIN"
fi

cat <<EOF

================ 安装摘要 ================
Xboard:       $XBOARD_DIR
Dujiao DB:    $DUJIAO_DB
Dujiao 配置:  $DUJIAO_CONFIG
商城域名:     $STORE_DOMAIN
节点域名:     $PANEL_DOMAIN
路由文件:     $XBOARD_ROUTE_FILE
Nginx 文件:   $STORE_NGINX_CONF
服务用户:     $SERVICE_USER:$SERVICE_GROUP
Xboard 运行:  $([[ -n "$XBOARD_DOCKER_CONTAINER" ]] && echo "Docker ($XBOARD_DOCKER_CONTAINER:$XBOARD_CONTAINER_DIR)" || echo 原生PHP)
前端安装:     $([[ -n "$DUJIAO_PUBLIC_DIR$XBOARD_PUBLIC_DIR" ]] && echo 是 || echo 否)
==========================================
EOF

if [[ $DRY_RUN -eq 1 ]]; then
  ok '预检通过。--dry-run 未修改任何文件或服务。'
  exit 0
fi

if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p '确认开始安装？输入 YES 继续: ' confirmation
  [[ "$confirmation" == YES ]] || die '用户取消安装'
fi

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/$PROJECT_NAME/$STAMP"
install -d -m 0700 "$BACKUP_DIR"

backup_file() {
  local source=$1 name=$2
  [[ -e "$source" ]] && cp -a "$source" "$BACKUP_DIR/$name"
}

log "备份现有配置到 $BACKUP_DIR"
backup_file "$XBOARD_DIR/.env" xboard.env
backup_file "$XBOARD_ROUTE_FILE" xboard-route.php
backup_file "$XBOARD_DIR/app/Http/Controllers/V1/Passport/GoSsoController.php" GoSsoController.php
backup_file "$STORE_NGINX_CONF" store-nginx.conf
backup_file /etc/systemd/system/dujiao-xboard-bridge.service systemd-service
backup_file /etc/dujiao-xboard-sso-bridge.env bridge.env
cp -a "$DUJIAO_DB" "$BACKUP_DIR/dujiao.db"
printf '%s\n' "$XBOARD_DIR" "$DUJIAO_DB" "$DUJIAO_CONFIG" "$XBOARD_ROUTE_FILE" "$STORE_NGINX_CONF" > "$BACKUP_DIR/paths.txt"
ok '备份完成'

set_env_value() {
  local file=$1 key=$2 value=$3 temporary
  temporary=$(mktemp)
  awk -v key="$key" -v value="$value" '
    BEGIN { found=0 }
    $0 ~ "^" key "=" { print key "=" value; found=1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" > "$temporary"
  cat "$temporary" > "$file"
  rm -f "$temporary"
}

log '安装 Xboard 控制器和路由'
install -m 0644 "$SCRIPT_DIR/xboard/GoSsoController.php" "$XBOARD_DIR/app/Http/Controllers/V1/Passport/GoSsoController.php"

if ! grep -Fq 'use App\Http\Controllers\V1\Passport\GoSsoController;' "$XBOARD_ROUTE_FILE"; then
  grep -Fq 'use App\Http\Controllers\V1\Passport\CommController;' "$XBOARD_ROUTE_FILE" || die 'Cannot locate the Passport route imports; the original route file was not changed'
  temporary=$(mktemp)
  awk '
    { print }
    /use App\\Http\\Controllers\\V1\\Passport\\CommController;/ {
      print "use App\\Http\\Controllers\\V1\\Passport\\GoSsoController;"
    }
  ' "$XBOARD_ROUTE_FILE" > "$temporary"
  cat "$temporary" > "$XBOARD_ROUTE_FILE"
  rm -f "$temporary"
fi

if ! grep -Fq "'/auth/goSso'" "$XBOARD_ROUTE_FILE"; then
  grep -Fq '// Comm' "$XBOARD_ROUTE_FILE" || {
    cp -a "$BACKUP_DIR/xboard-route.php" "$XBOARD_ROUTE_FILE"
    die 'Cannot locate the Passport route insertion point; the original route file was restored'
  }
  temporary=$(mktemp)
  awk '
    !inserted && /\/\/ Comm/ {
      print "            // Dujiao ↔ Xboard bridge"
      print "            $router->post(\047/auth/goSso\047, [GoSsoController::class, \047login\047]);"
      inserted=1
    }
    { print }
  ' "$XBOARD_ROUTE_FILE" > "$temporary"
  cat "$temporary" > "$XBOARD_ROUTE_FILE"
  rm -f "$temporary"
fi

set_env_value "$XBOARD_DIR/.env" DUJIAO_IDENTITY_URL "$DUJIAO_IDENTITY_URL"
set_env_value "$XBOARD_DIR/.env" DUJIAO_CREDENTIAL_URL "http://${BRIDGE_LISTEN}/credential.php"
set_env_value "$XBOARD_DIR/.env" DUJIAO_SSO_FAILURE_URL "https://${STORE_DOMAIN}/auth/login?sso=failed"

run_artisan() {
  if [[ -n "$XBOARD_DOCKER_CONTAINER" ]]; then
    docker exec -w "$XBOARD_CONTAINER_DIR" "$XBOARD_DOCKER_CONTAINER" php artisan "$@"
  else
    php "$XBOARD_DIR/artisan" "$@"
  fi
}

run_artisan optimize:clear >/dev/null
if ! run_artisan route:list 2>/dev/null | grep -q 'goSso'; then
  cp -a "$BACKUP_DIR/xboard-route.php" "$XBOARD_ROUTE_FILE"
  die 'Xboard did not load the new route. The route file was restored; adapt routes manually for this Xboard version.'
fi
if [[ -n "$XBOARD_DOCKER_CONTAINER" ]]; then
  docker restart "$XBOARD_DOCKER_CONTAINER" >/dev/null
  for _ in {1..30}; do
    [[ $(docker inspect --format '{{.State.Running}}' "$XBOARD_DOCKER_CONTAINER" 2>/dev/null) == true ]] && break
    sleep 1
  done
  [[ $(docker inspect --format '{{.State.Running}}' "$XBOARD_DOCKER_CONTAINER" 2>/dev/null) == true ]] || die 'Xboard Web container did not restart successfully'
fi
ok 'Xboard 路由已加载'

log '创建本机桥接服务'
cat > /etc/dujiao-xboard-sso-bridge.env <<EOF
DUJIAO_PUBLIC_URL=https://${STORE_DOMAIN}/
XBOARD_PUBLIC_URL=https://${PANEL_DOMAIN}/
DUJIAO_IDENTITY_URL=${DUJIAO_IDENTITY_URL}
DUJIAO_CREDENTIAL_URL=http://${BRIDGE_LISTEN}/credential.php
XBOARD_USER_INFO_URL=${XBOARD_USER_INFO_URL}
XBOARD_ENV_PATH=${XBOARD_DIR}/.env
DUJIAO_CONFIG_PATH=${DUJIAO_CONFIG}
DUJIAO_DATABASE_PATH=${DUJIAO_DB}
EOF
chown root:"$SERVICE_GROUP" /etc/dujiao-xboard-sso-bridge.env
chmod 0640 /etc/dujiao-xboard-sso-bridge.env

cat > /etc/systemd/system/dujiao-xboard-bridge.service <<EOF
[Unit]
Description=Dujiao and Xboard SSO Bridge
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${SCRIPT_DIR}/dujiao/public
EnvironmentFile=/etc/dujiao-xboard-sso-bridge.env
ExecStart=$(command -v php) -S ${BRIDGE_LISTEN} -t ${SCRIPT_DIR}/dujiao/public
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadOnlyPaths=${XBOARD_DIR}
ReadWritePaths=$(dirname "$DUJIAO_DB")

[Install]
WantedBy=multi-user.target
EOF

if ! runuser -u "$SERVICE_USER" -- test -r "$XBOARD_DIR/.env"; then
  die "$SERVICE_USER cannot read $XBOARD_DIR/.env. Fix group/ACL permissions and rerun; the backup is $BACKUP_DIR"
fi
if ! runuser -u "$SERVICE_USER" -- test -r "$DUJIAO_CONFIG"; then
  die "$SERVICE_USER cannot read $DUJIAO_CONFIG. Fix group/ACL permissions and rerun; the backup is $BACKUP_DIR"
fi
if ! runuser -u "$SERVICE_USER" -- test -r "$DUJIAO_DB" || ! runuser -u "$SERVICE_USER" -- test -w "$DUJIAO_DB" || ! runuser -u "$SERVICE_USER" -- test -w "$(dirname "$DUJIAO_DB")"; then
  die "$SERVICE_USER needs read/write access to the Dujiao DB and its directory. Do not use chmod 777; configure owner/group/ACL and rerun. Backup: $BACKUP_DIR"
fi

systemctl daemon-reload
systemctl enable --now dujiao-xboard-bridge.service
systemctl is-active --quiet dujiao-xboard-bridge.service || {
  systemctl status dujiao-xboard-bridge.service --no-pager || true
  die "Bridge service failed to start. Backup: $BACKUP_DIR"
}
ok '桥接服务运行正常'

log '安装 Nginx 固定 SSO 路由'
install -d -m 0755 /etc/nginx/snippets
cat > /etc/nginx/snippets/dujiao-xboard-sso-bridge.conf <<EOF
location = /sso/xboard {
    client_max_body_size 16k;
    proxy_pass http://${BRIDGE_LISTEN}/index.php;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    add_header Cache-Control "no-store" always;
}
EOF

NGINX_INCLUDE='include /etc/nginx/snippets/dujiao-xboard-sso-bridge.conf;'
if ! grep -Fq "$NGINX_INCLUDE" "$STORE_NGINX_CONF"; then
  temporary=$(mktemp)
  awk -v domain="$STORE_DOMAIN" -v include_line="    $NGINX_INCLUDE" '
    !inserted && $0 ~ /server_name/ && index($0, domain) { print; print include_line; inserted=1; next }
    { print }
    END { if (!inserted) exit 42 }
  ' "$STORE_NGINX_CONF" > "$temporary" || {
    rm -f "$temporary"
    die 'Could not safely insert the Nginx include. Original config was not changed.'
  }
  cat "$temporary" > "$STORE_NGINX_CONF"
  rm -f "$temporary"
fi

if ! nginx -t; then
  cp -a "$BACKUP_DIR/store-nginx.conf" "$STORE_NGINX_CONF"
  nginx -t || true
  die 'Nginx validation failed and the original site config was restored'
fi
systemctl reload nginx
ok 'Nginx 路由已生效'

render_production_template() {
  local source=$1 target=$2 content
  content=$(<"$source")
  content=${content//__PANEL_SSO_URL__/https:\/\/${PANEL_DOMAIN}\/api\/v1\/passport\/auth\/goSso}
  content=${content//__STORE_URL__/https:\/\/${STORE_DOMAIN}\/}
  content=${content//__STORE_SSO_URL__/https:\/\/${STORE_DOMAIN}\/sso\/xboard}
  content=${content//__TELEGRAM_URL__/$TELEGRAM_URL}
  content=${content//__TELEGRAM_HANDLE__/$TELEGRAM_HANDLE}
  content=${content//__PANEL_LOGO_URL__/\/assets\/dx-bridge\/panel-logo.png}
  content=${content//__STORE_LOGO_URL__/\/assets\/dx-bridge\/store-logo.png}
  printf '%s' "$content" > "$target"
}

install_frontend() {
  local site_name=$1 public_dir=$2 layout_file=$3 entry_file=$4 css_file=$5 logo_file=$6
  [[ -n "$public_dir" ]] || { warn "$site_name 未配置静态目录，跳过前端按钮"; return; }
  [[ -d "$public_dir" ]] || die "$site_name static directory not found: $public_dir"
  local asset_dir="$public_dir/assets/dx-bridge"
  install -d -m 0755 "$asset_dir"
  install -m 0644 "$SCRIPT_DIR/templates/production/$css_file" "$asset_dir/$css_file"
  install -m 0644 "$SCRIPT_DIR/templates/production/$logo_file" "$asset_dir/$logo_file"
  render_production_template "$SCRIPT_DIR/templates/production/$entry_file.tpl" "$asset_dir/$entry_file"

  [[ -n "$layout_file" ]] || { warn "$site_name 资源已安装，但没有布局文件；请手动引入 $asset_dir"; return; }
  [[ -f "$layout_file" ]] || die "$site_name layout file not found: $layout_file"
  backup_file "$layout_file" "${site_name}-layout"
  local marker="dx-bridge-${site_name}"
  if ! grep -Fq "$marker" "$layout_file"; then
    local temporary block inserted=0
    temporary=$(mktemp)
    block="<!-- $marker -->
<link rel=\"stylesheet\" href=\"/assets/dx-bridge/$css_file?v=$STAMP\">
<script defer src=\"/assets/dx-bridge/$entry_file?v=$STAMP\"></script>"
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ $inserted -eq 0 && "$line" == *'</body>'* ]]; then
        printf '%s\n' "$block" >> "$temporary"
        inserted=1
      fi
      printf '%s\n' "$line" >> "$temporary"
    done < "$layout_file"
    [[ $inserted -eq 1 ]] || { rm -f "$temporary"; die "$site_name layout has no </body>; frontend files were installed but HTML was not modified"; }
    cat "$temporary" > "$layout_file"
    rm -f "$temporary"
  fi
  ok "$site_name 前端入口已安装"
}

install_frontend dujiao "${DUJIAO_PUBLIC_DIR:-}" "${DUJIAO_LAYOUT_FILE:-}" go-xboard-bridge.js go-xboard-bridge.css panel-logo.png
install_frontend xboard "${XBOARD_PUBLIC_DIR:-}" "${XBOARD_LAYOUT_FILE:-}" xboard-shop-ai-store.js xboard-shop-ai-store.css store-logo.png

log '执行最终健康检查'
systemctl is-active --quiet dujiao-xboard-bridge.service || die 'Bridge service is not active'
ss -lnt 2>/dev/null | grep -Fq "$BRIDGE_LISTEN" || warn "无法从 ss 输出确认监听地址 $BRIDGE_LISTEN，请手动检查"
curl -fsSI --max-time 15 "https://${STORE_DOMAIN}/" >/dev/null || warn '商城首页 HTTP 检查失败'
curl -fsSI --max-time 15 "https://${PANEL_DOMAIN}/" >/dev/null || warn '节点首页 HTTP 检查失败'

cat <<EOF

安装完成。

备份目录：$BACKUP_DIR
服务状态：systemctl status dujiao-xboard-bridge.service
桥接日志：journalctl -u dujiao-xboard-bridge.service -n 100 --no-pager

请使用普通临时账号完成：
1. 商城 → 节点一键登录；
2. 节点 → 商城一键登录；
3. 退出后用同一邮箱和密码分别登录两个网站；
4. 检查手机端按钮没有挡住底部菜单。
EOF
