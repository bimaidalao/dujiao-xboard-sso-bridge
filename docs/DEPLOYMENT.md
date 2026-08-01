# 傻瓜式完整部署教程

本文面向第一次做二开的站长。每一步都说明“做什么、复制什么、看到什么算成功”。参考环境是：

- 同一台 Ubuntu 22.04/24.04 或 Debian 12 服务器；
- Nginx 对外提供两个 HTTPS 网站；
- Dujiao Next 使用 SQLite，内部 API 监听 `127.0.0.1:18080`；
- Xboard 使用 Laravel + MySQL/MariaDB + Redis，内部 API 监听 `127.0.0.1:7001`；
- 桥接服务使用 PHP，监听 `127.0.0.1:18081`。

如果两个网站不在同一台服务器，请不要照抄本教程开放数据库或凭据端口，应改用受控私网和双向认证。

## 第 0 步：确认版本与依赖

登录服务器后执行：

```bash
uname -a
nginx -v
php -v
php -m | grep -E 'curl|PDO|pdo_mysql|pdo_sqlite'
systemctl --version | head -1
```

至少应看到 `curl`、`PDO`、`pdo_mysql` 和 `pdo_sqlite`。缺少模块时，Ubuntu/Debian 可按实际 PHP 版本安装，例如：

```bash
sudo apt update
sudo apt install -y git curl php-cli php-curl php-mysql php-sqlite3
```

Xboard 本体需要的 PHP 版本以其上游要求为准；常见新版使用 PHP 8.2。桥接脚本兼容 PHP 7.4+。

## 第 1 步：找到两个项目的真实路径

先找 Xboard：

```bash
sudo find /www /opt /var/www -maxdepth 5 -type f -name artisan 2>/dev/null
```

进入疑似目录，确认存在 `app/`、`routes/`、`vendor/` 和 `.env`：

```bash
cd /你的/Xboard/目录
pwd
ls -la
php artisan --version
```

再找 Dujiao SQLite 数据库和配置：

```bash
sudo find /www /opt /var/www -type f \( -name 'dujiao.db' -o -name 'config.yml' \) 2>/dev/null
```

找不到时，查看正在运行的服务或容器：

```bash
systemctl --type=service --state=running | grep -Ei 'dujiao|xboard|php|docker'
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || true
```

## 第 2 步：填写自己的路径参数

下面只是示例。请把域名和路径换成自己的，再逐行执行：

```bash
export BRIDGE_DIR=/opt/dujiao-xboard-sso-bridge
export XBOARD_DIR=/opt/xboard
export DUJIAO_DIR=/opt/dujiao-next
export DUJIAO_DB=/opt/dujiao-next/db/dujiao.db
export DUJIAO_CONFIG=/opt/dujiao-next/config.yml
export STORE_DOMAIN=store.example.com
export PANEL_DOMAIN=panel.example.com
```

立即检查，任何一项显示 `NOT FOUND` 都不要继续：

```bash
test -f "$XBOARD_DIR/artisan" && echo 'Xboard: OK' || echo 'Xboard: NOT FOUND'
test -f "$XBOARD_DIR/.env" && echo 'Xboard .env: OK' || echo 'Xboard .env: NOT FOUND'
test -f "$DUJIAO_DB" && echo 'Dujiao DB: OK' || echo 'Dujiao DB: NOT FOUND'
test -f "$DUJIAO_CONFIG" && echo 'Dujiao config: OK' || echo 'Dujiao config: NOT FOUND'
```

## 第 3 步：下载代码并创建备份

```bash
cd /opt
sudo git clone https://github.com/bimaidalao/dujiao-xboard-sso-bridge.git
cd "$BRIDGE_DIR"
```

如果目录已经存在：

```bash
cd "$BRIDGE_DIR"
sudo git pull --ff-only
```

创建时间戳备份目录：

```bash
export BACKUP_DIR=/root/dujiao-xboard-backup-$(date +%Y%m%d-%H%M%S)
sudo install -d -m 0700 "$BACKUP_DIR"
sudo cp -a "$XBOARD_DIR/.env" "$BACKUP_DIR/xboard.env"
sudo cp -a "$DUJIAO_DB" "$BACKUP_DIR/dujiao.db"
sudo cp -a "$DUJIAO_CONFIG" "$BACKUP_DIR/dujiao-config.yml"
echo "备份位置：$BACKUP_DIR"
```

再备份 Xboard 用户表。命令会提示输入数据库密码，不要把密码写进脚本或聊天记录：

```bash
grep -E '^DB_(HOST|PORT|DATABASE|USERNAME)=' "$XBOARD_DIR/.env"
mysqldump -h 数据库地址 -u 数据库用户 -p 数据库名称 v2_user > "$BACKUP_DIR/xboard-v2_user.sql"
```

## 第 4 步：安装 Xboard 端控制器

先查找当前版本 Passport 控制器目录：

```bash
sudo find "$XBOARD_DIR/app" -type d -path '*Controllers*Passport*'
```

常见目标是：

```text
app/Http/Controllers/V1/Passport/
```

确认后设置变量并复制：

```bash
export XBOARD_PASSPORT_DIR="$XBOARD_DIR/app/Http/Controllers/V1/Passport"
sudo cp -a "$XBOARD_PASSPORT_DIR" "$BACKUP_DIR/xboard-passport-controllers"
sudo install -m 0644 "$BRIDGE_DIR/xboard/GoSsoController.php" "$XBOARD_PASSPORT_DIR/GoSsoController.php"
```

打开 Xboard 的 Passport 路由文件：

```bash
grep -RIn "Passport" "$XBOARD_DIR/routes" | head -30
```

在已有 Passport 路由组内加入以下内容；不要直接覆盖整个路由文件：

```php
use App\Http\Controllers\V1\Passport\GoSsoController;

$router->post('/auth/dujiao-sso', [GoSsoController::class, 'login']);
```

仓库中的可复制片段位于 `xboard/routes.php.snippet`。

向 Xboard `.env` 末尾加入三项：

```dotenv
DUJIAO_IDENTITY_URL=http://127.0.0.1:18080/api/v1/me
DUJIAO_CREDENTIAL_URL=http://127.0.0.1:18081/credential.php
DUJIAO_SSO_FAILURE_URL=https://store.example.com/auth/login?sso=failed
```

把 `store.example.com` 改成自己的商城域名。随后清缓存并检查路由：

```bash
cd "$XBOARD_DIR"
php artisan optimize:clear
php artisan route:list | grep -i dujiao
```

成功标准：输出中存在 `POST` 和 `auth/dujiao-sso`。如果 Xboard 在 Docker 中，请在 PHP/Web 容器里执行 `php artisan optimize:clear`，然后重启该容器。

## 第 5 步：配置 Dujiao 桥接服务

先生成环境文件：

```bash
sudo tee /etc/dujiao-xboard-sso-bridge.env >/dev/null <<EOF
DUJIAO_PUBLIC_URL=https://${STORE_DOMAIN}/
XBOARD_PUBLIC_URL=https://${PANEL_DOMAIN}/
DUJIAO_IDENTITY_URL=http://127.0.0.1:18080/api/v1/me
DUJIAO_CREDENTIAL_URL=http://127.0.0.1:18081/credential.php
XBOARD_USER_INFO_URL=http://127.0.0.1:7001/api/v1/user/info
XBOARD_ENV_PATH=${XBOARD_DIR}/.env
DUJIAO_CONFIG_PATH=${DUJIAO_CONFIG}
DUJIAO_DATABASE_PATH=${DUJIAO_DB}
EOF
sudo chmod 0640 /etc/dujiao-xboard-sso-bridge.env
sudo chown root:www-data /etc/dujiao-xboard-sso-bridge.env
```

检查文件中只有正确的域名、路径和本机地址：

```bash
sudo sed -n '1,20p' /etc/dujiao-xboard-sso-bridge.env
```

确保 Web 用户可以读取必要文件，并且 SQLite 所在目录允许 Dujiao 正常写入。不要直接使用 `chmod -R 777`。

安装 systemd 服务：

```bash
sudo cp "$BRIDGE_DIR/deploy/dujiao-xboard-bridge.service.example" /etc/systemd/system/dujiao-xboard-bridge.service
sudo nano /etc/systemd/system/dujiao-xboard-bridge.service
```

需要核对并修改这几行：

```ini
WorkingDirectory=/opt/dujiao-xboard-sso-bridge/dujiao/public
ExecStart=/usr/bin/php -S 127.0.0.1:18081 -t /opt/dujiao-xboard-sso-bridge/dujiao/public
ReadOnlyPaths=/opt/xboard
ReadWritePaths=/opt/dujiao-next/db
```

把 `/opt/xboard` 和 `/opt/dujiao-next/db` 改成第 2 步填写的真实路径。如果系统的 PHP 不在 `/usr/bin/php`，先执行 `command -v php` 并替换 `ExecStart`。

启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now dujiao-xboard-bridge.service
sudo systemctl status dujiao-xboard-bridge.service --no-pager
ss -lntp | grep 18081
```

成功标准：服务显示 `active (running)`，并且 `18081` 只绑定 `127.0.0.1`，不能绑定 `0.0.0.0`。

## 第 6 步：添加 Nginx 路由

找到商城 Nginx 配置：

```bash
sudo nginx -T 2>/dev/null | grep -n "server_name ${STORE_DOMAIN}"
```

在商城域名的 `server { ... }` 内加入：

```nginx
location = /sso/xboard {
    client_max_body_size 16k;
    proxy_pass http://127.0.0.1:18081/index.php;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    add_header Cache-Control "no-store" always;
}
```

不要为 `/credential.php` 添加公网代理，它只能由服务器本机访问。

检查并重载：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

如果 `nginx -t` 报错，立即撤销刚才加入的配置；不要强制重启 Nginx。

## 第 7 步：安装前端跨站入口

需要把以下三个文件放到两个站点能公开访问的静态资源目录：

```text
frontend/config.example.js
frontend/bridge.css
frontend/dujiao-entry.js
frontend/xboard-entry.js
```

先复制配置并修改域名：

```bash
cd "$BRIDGE_DIR"
sudo cp frontend/config.example.js frontend/bridge-config.js
sudo nano frontend/bridge-config.js
```

配置示例：

```js
window.DujiaoXboardBridge = {
  xboardSsoUrl: 'https://panel.example.com/api/v1/passport/auth/dujiao-sso',
  xboardLoginUrl: 'https://panel.example.com/#/login',
  dujiaoSsoUrl: 'https://store.example.com/sso/xboard',
  dujiaoLoginUrl: 'https://store.example.com/auth/login',
  storeLabel: 'AI 工具/账号商店',
  panelLabel: 'AI 专用加速器 VPN 节点'
};
```

把 `panel.example.com`、`store.example.com` 改成自己的域名。

在 Dujiao 主题的全局自定义 HTML、页脚模板或入口文件中按顺序加载：

```html
<link rel="stylesheet" href="/assets/bridge.css?v=1">
<script src="/assets/bridge-config.js?v=1"></script>
<script defer src="/assets/dujiao-entry.js?v=1"></script>
```

在 Xboard 主题中加载：

```html
<link rel="stylesheet" href="/assets/bridge.css?v=1">
<script src="/assets/bridge-config.js?v=1"></script>
<script defer src="/assets/xboard-entry.js?v=1"></script>
```

主题没有“自定义 HTML”功能时，需要在源码布局文件或构建入口引入。不同主题的 DOM 结构不同，先在测试环境确认位置；不要直接覆盖主题整包。

每次修改脚本后把 `?v=1` 改为 `?v=2`，避免浏览器继续使用旧缓存。

## 第 8 步：基础健康检查

```bash
systemctl is-active dujiao-xboard-bridge.service
curl -I "https://${STORE_DOMAIN}/"
curl -I "https://${PANEL_DOMAIN}/"
curl -i -X POST "https://${STORE_DOMAIN}/sso/xboard"
```

预期结果：

- 服务返回 `active`；
- 两个首页返回 `200` 或正常的 `301/302`；
- 未携带登录数据访问 SSO 路由应跳到登录页，而不是显示 PHP 源码；
- 公网访问 `https://商城域名/credential.php` 应为 `404` 或拒绝访问。

查看错误日志：

```bash
journalctl -u dujiao-xboard-bridge.service -n 100 --no-pager
tail -n 100 "$XBOARD_DIR/storage/logs/laravel.log"
```

## 第 9 步：用临时账号验收

不要先拿管理员账号测试。新建一个普通、已验证邮箱账号，按顺序操作：

1. 登录商城，点击节点入口，应自动进入节点仪表盘。
2. 退出节点网站，用商城邮箱和密码直接登录节点网站。
3. 修改节点密码，然后点击“进入 AI 工具/账号商店”。
4. 退出商城，用刚修改的节点密码直接登录商城。
5. 检查两个网站显示相同邮箱。
6. 禁用测试账号，确认不能继续通过 SSO。
7. 在手机浏览器检查卡片不挡底部菜单、不与回到顶部按钮重叠。
8. 日间和夜间各检查一次入口颜色与可读性。

旧账号两边密码不一致时，**从哪一边发起跨站登录，就保留哪一边的密码**。不要对全部旧用户做没有通知的批量覆盖。

## 第 10 步：回滚

先停止新增桥接流量：

```bash
sudo systemctl disable --now dujiao-xboard-bridge.service
```

然后：

1. 从 Nginx 商城配置中删除 `/sso/xboard` location，执行 `sudo nginx -t && sudo systemctl reload nginx`。
2. 恢复 `$BACKUP_DIR/xboard-passport-controllers` 中的控制器，并删除新增路由。
3. 恢复 `$BACKUP_DIR/xboard.env`，再执行 `php artisan optimize:clear`。
4. 必要时恢复 `$BACKUP_DIR/dujiao.db` 和 `xboard-v2_user.sql`；恢复数据库前必须再次备份当前数据。
5. 移除两个主题加载的桥接 JS/CSS。
6. 确认两个网站原有登录、下单、支付和节点订阅功能正常。

## 常见失败位置

| 现象 | 先检查 |
| --- | --- |
| 点击后回到登录页 | 浏览器 Token 名、目标 URL、来源账号是否已验证 |
| Xboard 返回 404 | Laravel 路由片段是否在正确路由组、是否清过缓存 |
| 桥接服务启动失败 | PHP 路径、WorkingDirectory、环境文件权限 |
| 500 或数据库错误 | `pdo_mysql`、`pdo_sqlite`、Xboard `.env` 路径与权限 |
| 一键登录成功但密码不同 | 两边是否同邮箱、哈希是否为 bcrypt、是否从想保留密码的一侧发起 |
| 手机端无法滑动 | 透明容器是否接收 pointer event、旧主题 CSS 是否缓存 |

更多错误日志关键词和处理方式见 [故障排查](TROUBLESHOOTING.md)。
