# Telegram 双向媒体工单

该目录是与当前生产 Xboard v0.3.8 同源的工单覆盖层，实现：

- 新工单、用户追问实时推送到 Telegram；
- 引用任意带“#工单号”的通知即可回复原工单；
- 文字、Unicode 表情、静态/视频贴纸、图片和视频双向同步；
- Telegram 关闭按钮同步关闭网站工单；
- 每条最多 4 个媒体，单文件最大 20MB；
- 媒体保存在 Xboard 私有存储，通过登录鉴权读取；
- Webhook 密钥、Chat ID 与 Telegram 管理员 ID 三层限制；
- 手机端上传入口位于回复框上方，不遮挡底部导航。

## 文件结构

- `app/`：媒体模型、上传接口、Telegram Webhook 与工单服务；
- `config/telegram_ticket.php`：只读取环境变量，不包含密钥；
- `database/migrations/`：新增 `v2_ticket_media`，不修改已有工单表；
- `public/assets/`：图片/表情包/视频选择、上传与消息内预览；
- `install.sh`：备份、安装、迁移、清缓存及可选 Webhook 注册。

## 安装

先备份数据库，并确认目标为项目文档声明的 Xboard 版本。该覆盖层包含当前生产控制器，已有二开项目应先比较差异。

```bash
export XBOARD_DIR=/www/wwwroot/xboard
export XBOARD_PHP_CMD='docker exec xboard-web php'
export TELEGRAM_TICKET_CHAT_ID='123456789'
export TELEGRAM_TICKET_ALLOWED_USER_IDS='123456789'
export TELEGRAM_TICKET_ADMIN_URL='https://panel.example.com/admin'
export TELEGRAM_TICKET_WEBHOOK_URL='https://panel.example.com/api/v1/telegram/ticket/webhook'
sudo -E bash xboard/telegram-ticket/install.sh
```

安装器会交互读取 Bot Token，不会把 Token 写入仓库。若 Xboard 不在 Docker 中，将 `XBOARD_PHP_CMD` 设为 `php`。

## Telegram 设置

1. 用 BotFather 创建独立客服机器人；
2. 私聊机器人发送 `/start`，用 Bot API `getUpdates` 取得数字 Chat ID；
3. 配置允许操作工单的 Telegram 用户 ID；
4. 注册 Webhook，必须设置 `secret_token`；
5. 创建测试工单，分别验证文字、图片和视频的双向同步。

## 安全限制

- 默认不支持可执行文件、HTML、SVG、脚本和任意文档；
- 支持 JPG、PNG、GIF、WEBP、MP4、WEBM、MOV；
- Telegram 官方 Bot API 下载上限为 20MB，因此双向同步统一按 20MB 限制；
- 动态 TGS 贴纸需要额外渲染器，当前提示改发图片、GIF 或视频贴纸；
- Token 只能放在服务器 `.env`，截图泄露后必须立即在 BotFather 重新生成；
- 上传接口要求 Xboard 登录，媒体读取同时校验所属用户。

## 回滚

安装前文件位于：

```text
<XBOARD_DIR>/storage/backups/telegram-ticket-时间戳/
```

恢复备份文件后执行：

```bash
php artisan optimize:clear
php artisan octane:reload
```

如果需要删除新表，先确认没有需要保留的媒体记录，再回滚对应迁移。