#!/usr/bin/env bash

log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

prompt_value() {
  local variable=$1 label=$2 default=${3:-} value=''
  value=${!variable:-}
  if [[ -z "$value" && ${ASSUME_YES:-0} -eq 0 ]]; then
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
  if [[ -z "$value" && ${ASSUME_YES:-0} -eq 0 ]]; then
    read -r -p "$label${default:+ [$default]} (留空跳过): " value
    value=${value:-$default}
  fi
  printf -v "$variable" '%s' "$value"
}

first_match() { find "$@" 2>/dev/null | head -n 1 || true; }

backup_file() {
  local source=$1 name=$2
  [[ -e "$source" ]] && cp -a "$source" "$BACKUP_DIR/$name"
}

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

run_artisan() {
  if [[ -n ${XBOARD_DOCKER_CONTAINER:-} ]]; then
    docker exec -w "$XBOARD_CONTAINER_DIR" "$XBOARD_DOCKER_CONTAINER" php artisan "$@"
  else
    php "$XBOARD_DIR/artisan" "$@"
  fi
}

render_production_template() {
  local source=$1 target=$2 content
  content=$(<"$source")
  content=${content//__PANEL_SSO_URL__/https:\/\/${PANEL_DOMAIN}\/api\/v1\/passport\/auth\/goSso}
  content=${content//__STORE_URL__/https:\/\/${STORE_DOMAIN}\/}
  content=${content//__STORE_SSO_URL__/https:\/\/${STORE_DOMAIN}\/sso\/xboard}
  content=${content//__STORE_ORDER_API__/https:\/\/${STORE_DOMAIN}\/sso\/orders}
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
