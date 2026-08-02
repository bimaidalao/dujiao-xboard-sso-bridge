#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=${XBOARD_DIR:-${1:-}}
[[ -n $ROOT_DIR && -f $ROOT_DIR/artisan ]] || { echo '用法: XBOARD_DIR=/path/to/xboard bash install.sh'; exit 1; }
SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PHP_CMD=${XBOARD_PHP_CMD:-php}
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$ROOT_DIR/storage/backups/telegram-ticket-$STAMP"
mkdir -p "$BACKUP_DIR"

read_value() {
  local name=$1 prompt=$2 secret=${3:-0} value=${!name:-}
  if [[ -z $value ]]; then
    if [[ $secret == 1 ]]; then read -r -s -p "$prompt: " value; echo
    else read -r -p "$prompt: " value; fi
  fi
  printf -v "$name" '%s' "$value"
}

read_value TELEGRAM_TICKET_BOT_TOKEN 'Telegram Bot Token' 1
read_value TELEGRAM_TICKET_CHAT_ID 'Telegram Chat ID'
TELEGRAM_TICKET_ALLOWED_USER_IDS=${TELEGRAM_TICKET_ALLOWED_USER_IDS:-$TELEGRAM_TICKET_CHAT_ID}
TELEGRAM_TICKET_ADMIN_URL=${TELEGRAM_TICKET_ADMIN_URL:-}
TELEGRAM_TICKET_WEBHOOK_SECRET=${TELEGRAM_TICKET_WEBHOOK_SECRET:-$(openssl rand -hex 32)}

files=(
  app/Models/TicketMedia.php
  app/Http/Controllers/V1/User/TicketMediaController.php
  app/Http/Controllers/V1/User/TicketController.php
  app/Http/Controllers/V1/Guest/TelegramTicketController.php
  app/Services/TelegramTicketService.php
  app/Services/TicketService.php
  app/Http/Requests/User/TicketSave.php
  app/Http/Routes/V1/UserRoute.php
  app/Http/Routes/V1/TelegramTicketRoute.php
  config/telegram_ticket.php
  database/migrations/2026_08_02_130000_create_v2_ticket_media_table.php
  public/assets/order-ticket-ui.js
  public/assets/order-ticket-ui.css
)

for relative in "${files[@]}"; do
  source_file="$SOURCE_DIR/$relative"
  target_file="$ROOT_DIR/$relative"
  [[ -f $source_file ]] || { echo "缺少发布文件: $source_file"; exit 1; }
  if [[ -f $target_file ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
    cp -a "$target_file" "$BACKUP_DIR/$relative"
  fi
  install -D -m 0644 "$source_file" "$target_file"
done

upsert_env() {
  local key=$1 value=$2 env_file="$ROOT_DIR/.env" escaped
  escaped=$(printf '%s' "$value" | sed 's/[&|]/\\&/g')
  if grep -q "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${escaped}|" "$env_file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

upsert_env TELEGRAM_TICKET_ENABLED true
upsert_env TELEGRAM_TICKET_BOT_TOKEN "$TELEGRAM_TICKET_BOT_TOKEN"
upsert_env TELEGRAM_TICKET_CHAT_ID "$TELEGRAM_TICKET_CHAT_ID"
upsert_env TELEGRAM_TICKET_ALLOWED_USER_IDS "$TELEGRAM_TICKET_ALLOWED_USER_IDS"
upsert_env TELEGRAM_TICKET_WEBHOOK_SECRET "$TELEGRAM_TICKET_WEBHOOK_SECRET"
upsert_env TELEGRAM_TICKET_XBOARD_ADMIN_USER_ID "${TELEGRAM_TICKET_XBOARD_ADMIN_USER_ID:-0}"
upsert_env TELEGRAM_TICKET_ADMIN_URL "$TELEGRAM_TICKET_ADMIN_URL"

index_file="$ROOT_DIR/public/index.html"
if [[ -f $index_file ]]; then
  cp -a "$index_file" "$BACKUP_DIR/index.html"
  grep -q 'order-ticket-ui.css' "$index_file" || sed -i 's#</head>#<link rel="stylesheet" href="/assets/order-ticket-ui.css?v=telegram-media">\n</head>#' "$index_file"
  grep -q 'order-ticket-ui.js' "$index_file" || sed -i 's#</body>#<script defer src="/assets/order-ticket-ui.js?v=telegram-media"></script>\n</body>#' "$index_file"
fi

cd "$ROOT_DIR"
bash -lc "$PHP_CMD artisan migrate --force"
bash -lc "$PHP_CMD artisan optimize:clear"
bash -lc "$PHP_CMD artisan octane:reload" 2>/dev/null || true

WEBHOOK_URL=${TELEGRAM_TICKET_WEBHOOK_URL:-}
if [[ -n $WEBHOOK_URL ]]; then
  curl -fsS "https://api.telegram.org/bot${TELEGRAM_TICKET_BOT_TOKEN}/setWebhook" \
    -H 'Content-Type: application/json' \
    -d "{\"url\":\"${WEBHOOK_URL}\",\"secret_token\":\"${TELEGRAM_TICKET_WEBHOOK_SECRET}\",\"allowed_updates\":[\"message\",\"callback_query\"]}" >/dev/null
fi

echo "安装完成。备份目录: $BACKUP_DIR"
echo '请创建一张测试工单，并从 Telegram 引用回复文字、图片或视频。'
