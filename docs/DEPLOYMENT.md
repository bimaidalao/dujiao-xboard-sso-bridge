# 完整部署流程

本文按“同一台 Linux 服务器、Nginx 对外、Dujiao Next 使用 SQLite、Xboard 使用 MySQL/Redis”的参考环境编写。路径和端口均为示例。

## 1. 参考环境

| 组件 | 参考配置 |
| --- | --- |
| 系统 | Ubuntu 22.04/24.04、Debian 12 |
| Web | Nginx 1.20+，两个域名均启用 HTTPS |
| 商城 | Dujiao Next，内部 API `127.0.0.1:18080` |
| 节点 | Xboard/Laravel，内部 API `127.0.0.1:7001` |
| 桥接 | PHP 7.4+，监听 `127.0.0.1:18081` |
| 数据库 | Dujiao SQLite；Xboard MySQL/MariaDB |
| 缓存 | Redis（由 Xboard 使用） |
| 服务管理 | systemd |

## 2. 部署前检查

```bash
php -v
php -m | grep -E 'curl|PDO|pdo_mysql|pdo_sqlite'
nginx -t
curl -fsS http://127.0.0.1:18080/api/v1/me || true
curl -fsS http://127.0.0.1:7001/api/v1/guest/comm/config
```

必须先备份：

- Dujiao SQLite 数据库与应用配置；
- Xboard 用户表、控制器、路由及 `.env`；
- Nginx 站点配置；
- 已存在的桥接目录和 systemd unit。

## 3. 环境变量

复制 `.env.example`，按实际路径修改：

```dotenv
DUJIAO_PUBLIC_URL=https://store.example.com/
XBOARD_PUBLIC_URL=https://panel.example.com/

DUJIAO_IDENTITY_URL=http://127.0.0.1:18080/api/v1/me
DUJIAO_CREDENTIAL_URL=http://127.0.0.1:18081/credential.php
XBOARD_USER_INFO_URL=http://127.0.0.1:7001/api/v1/user/info

DUJIAO_CONFIG_PATH=/opt/dujiao-next/config.yml
DUJIAO_DATABASE_PATH=/opt/dujiao-next/db/dujiao.db
XBOARD_ENV_PATH=/opt/xboard/.env
```

权限建议：

```bash
sudo install -m 0640 -o root -g www-data .env /etc/dujiao-xboard-sso-bridge.env
sudo chown -R root:www-data /opt/dujiao-xboard-sso-bridge
sudo find /opt/dujiao-xboard-sso-bridge -type f -exec chmod 0640 {} \;
```

## 4. 安装 Xboard 端

1. 将 `xboard/GoSsoController.php` 复制到当前版本的 Passport 控制器目录。
2. 按 `xboard/routes.php.snippet` 添加 POST 路由。
3. 核对 `User` 模型、`UserService`、`LoginService` 的命名空间。
4. 确认用户表字段包含 `email`、`password`、`password_algo`、`password_salt`、`banned`。

```bash
php artisan route:list | grep -i dujiao
php artisan optimize:clear
```

如果 Xboard 在 Docker 中，修改宿主机绑定的源码后重启 Web 容器，等待 API 连续三次返回 200 再测试。

## 5. 安装 Dujiao 桥接

```bash
sudo install -d -m 0750 -o root -g www-data /opt/dujiao-xboard-sso-bridge/dujiao/public
sudo install -m 0640 dujiao/public/index.php /opt/dujiao-xboard-sso-bridge/dujiao/public/index.php
sudo install -m 0640 dujiao/public/credential.php /opt/dujiao-xboard-sso-bridge/dujiao/public/credential.php
sudo install -m 0644 deploy/dujiao-xboard-bridge.service.example /etc/systemd/system/dujiao-xboard-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable --now dujiao-xboard-bridge.service
```

验证服务只监听本机：

```bash
ss -lntp | grep 18081
systemctl status dujiao-xboard-bridge.service
```

## 6. Nginx

参考 `deploy/nginx.conf.example`，只公开固定的 `/sso/xboard` 路径。`credential.php` 不得添加公网代理规则。

```bash
sudo nginx -t
sudo systemctl reload nginx
```

建议增加：

- `client_max_body_size 16k`；
- 每 IP 速率限制；
- `X-Forwarded-Proto`；
- HSTS；
- 对 SSO 响应禁用缓存。

## 7. 前端入口

加载顺序：

```html
<link rel="stylesheet" href="/assets/bridge.css">
<script src="/assets/bridge-config.js"></script>
<script defer src="/assets/dujiao-entry.js"></script>
```

Xboard 使用 `xboard-entry.js`。修改资源后务必更新查询版本号，避免浏览器继续使用旧缓存。

## 8. 上线验证

使用临时邮箱执行以下测试，完成后删除测试账号：

1. Xboard 登录 → 一键进入 Dujiao；
2. Dujiao 登录 → 一键进入 Xboard；
3. 两个系统显示相同邮箱；
4. 同一密码可以分别通过两个系统的原生密码校验；
5. 禁用账号无法通过 SSO；
6. 非白名单 redirect 回到默认页面；
7. 手机端没有透明遮罩，底部导航可以滑动和点击；
8. 两个公开站点返回 200，内部凭据地址从公网不可访问。

## 9. 回滚

部署时为每个覆盖文件生成时间戳备份：

```bash
cp index.php index.php.bak-$(date +%Y%m%d-%H%M%S)
```

若验证失败：

1. 恢复 Xboard 控制器和路由；
2. 恢复 Dujiao 桥接入口；
3. 删除新增加的内部凭据文件；
4. 恢复 systemd unit；
5. `systemctl daemon-reload` 并重启桥接；
6. 重启 Xboard Web 容器；
7. 再次检查两个公开站点和原有 SSO。

