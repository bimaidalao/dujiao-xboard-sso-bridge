# 傻瓜式完整部署教程

本文对应 `v1.0.0` 成品仓库。推荐让 Dujiao Next 与 Xboard 位于同一台 Linux 服务器；安装器支持 Xboard 原生 PHP、Docker host 网络和普通 Docker bridge 网络。

## 1. 部署前准备

必须具备：

- Ubuntu 20.04/22.04/24.04 或 Debian 11/12；
- root 或 sudo 权限；
- 已经能正常访问的 Dujiao Next 与 Xboard；
- 两个启用 HTTPS 的域名；
- Dujiao SQLite 数据库和 `config.yml`；
- Xboard 项目目录、`.env`、Web 容器（如使用 Docker）；
- PHP 7.4+，并启用 `curl`、`PDO`、`pdo_mysql`、`pdo_sqlite`；
- Xboard 使用其上游要求的 PHP，当前版本按 PHP 8.2+ 校验；
- Nginx 与 systemd。

先确认基础依赖：

```bash
php -v
php -m | grep -E 'curl|PDO|pdo_mysql|pdo_sqlite'
nginx -v
systemctl --version | head -1
docker ps 2>/dev/null || true
```

两个系统不在同一台服务器时，不要直接开放数据库、SQLite、密码哈希或 `18081` 端口。当前一键安装器只承诺同机或受控私网部署。

## 2. 一条命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/bimaidalao/dujiao-xboard-sso-bridge/main/bootstrap.sh | sudo bash
```

安装器会依次询问并确认：

1. Xboard 根目录；
2. Dujiao 数据库和配置文件；
3. 商城域名与节点域名；
4. Telegram 客服地址；
5. Xboard 路由文件和 Docker Web 容器；
6. Nginx 商城站点配置；
7. 运行桥接服务的 Linux 用户；
8. 两个网站的静态资源和 `index.html`。

确认摘要后才会写入文件。安装器会自动：

- 建立时间戳备份；
- 安装双向 SSO 控制器和路由；
- 安装工单双系统最近订单摘要；
- 运行数据库迁移；
- 写入桥接环境与 systemd 服务；
- 注入 Nginx 固定路由；
- 安装桌面端与手机端组件；
- 验证路由、服务、Nginx 和网站状态；
- 写入 `/var/lib/dujiao-xboard-sso-bridge/state.env`。

## 3. 先检查、不修改服务器

希望先看自动识别结果：

```bash
sudo /opt/dujiao-xboard-sso-bridge/bin/dx-bridge install --dry-run
```

成功标准是出现安装摘要和：

```text
[ OK ] 预检通过。--dry-run 未修改任何文件或服务。
```

路径、域名、容器或 Nginx 文件有任何一项不正确，都不要继续正式安装。

## 4. 无人值守配置

```bash
cd /opt/dujiao-xboard-sso-bridge
cp install.env.example install.env
nano install.env
sudo bin/dx-bridge install --config install.env --yes --dry-run
sudo bin/dx-bridge install --config install.env --yes
```

重点参数：

| 参数 | 用途 |
| --- | --- |
| `XBOARD_DIR` | Xboard 宿主机项目目录 |
| `DUJIAO_DB` | Dujiao SQLite 文件 |
| `DUJIAO_CONFIG` | Dujiao `config.yml` |
| `STORE_DOMAIN` | AI 工具商城域名，不含协议 |
| `PANEL_DOMAIN` | 节点网站域名，不含协议 |
| `XBOARD_DOCKER_CONTAINER` | Xboard Web 容器名；原生部署留空 |
| `XBOARD_CONTAINER_DIR` | Xboard 在容器内的工作目录 |
| `STORE_NGINX_CONF` | 商城 HTTPS server block 配置 |
| `SERVICE_USER/GROUP` | 可访问 Dujiao DB 的最小权限用户 |
| `BRIDGE_CLIENT_URL` | 通常留空，由安装器根据 Docker 网络生成 |
| `BRIDGE_TRUSTED_CLIENTS` | 允许读取密码哈希的本机或私网地址/CIDR |

不要把填写完成的 `install.env` 提交到 GitHub。

## 5. Docker 网络说明

### host 网络

容器和宿主机共享网络，桥接默认监听 `127.0.0.1:18081`。密码哈希接口只允许本机访问。

### bridge 网络

安装器会读取容器所在 Docker network 的网关和子网：

- 桥接监听调整为 `0.0.0.0:18081`；
- Xboard 通过 Docker 网关访问桥接；
- `credential.php` 仅信任 localhost 和检测到的 Docker CIDR；
- Nginx 仍通过 `127.0.0.1:18081` 反向代理。

即使应用层有限制，也应在云防火墙或主机防火墙禁止公网访问 `18081/tcp`。

## 6. 安装后检查

```bash
sudo /opt/dujiao-xboard-sso-bridge/bin/dx-bridge check
sudo systemctl status dujiao-xboard-bridge.service --no-pager
sudo journalctl -u dujiao-xboard-bridge.service -n 100 --no-pager
sudo nginx -t
```

随后用专门的普通测试账号完成：

1. 商城登录后跳转节点网站；
2. 节点网站登录后跳转商城；
3. 退出两个网站，使用相同邮箱和密码分别独立登录；
4. 创建工单，确认自动附带节点与商城各自最近一笔订单；
5. 确认订单摘要没有卡密、密码和自动发货正文；
6. 手机端打开、滑动、输入和提交工单；
7. 检查悬浮卡片不遮挡底部导航与输入框。

不要使用管理员账号做首次验收。

## 7. 更新

```bash
cd /opt/dujiao-xboard-sso-bridge
sudo bin/dx-bridge validate
sudo bin/dx-bridge update --config install.env --yes
sudo bin/dx-bridge check
```

更新前工作目录必须没有未提交修改。安装器会重新建立备份；检测到不兼容的路由、权限或 Nginx 结构时会停止。

## 8. 回滚

恢复最近一次程序和配置备份：

```bash
sudo /opt/dujiao-xboard-sso-bridge/bin/dx-bridge rollback
```

指定某个备份：

```bash
sudo bin/dx-bridge rollback --backup /var/backups/dujiao-xboard-sso-bridge/时间戳
```

默认不会恢复 Dujiao 数据库，避免覆盖安装后新增的订单。只有明确确认需要数据库回滚时才使用：

```bash
sudo bin/dx-bridge rollback --with-db
```

## 9. 文件位置

| 内容 | 默认位置 |
| --- | --- |
| 项目 | `/opt/dujiao-xboard-sso-bridge` |
| 桥接环境 | `/etc/dujiao-xboard-sso-bridge.env` |
| systemd 服务 | `/etc/systemd/system/dujiao-xboard-bridge.service` |
| Nginx 片段 | `/etc/nginx/snippets/dujiao-xboard-sso-bridge.conf` |
| 安装状态 | `/var/lib/dujiao-xboard-sso-bridge/state.env` |
| 时间戳备份 | `/var/backups/dujiao-xboard-sso-bridge/` |

## 10. 常见失败处理

- `401/403`：检查登录 Token、邮箱验证状态和账号禁用状态；
- Docker 中访问 `127.0.0.1` 失败：不要手改公网端口，重新运行 dry-run 检查网络模式和 `BRIDGE_CLIENT_URL`；
- 凭据接口 `403`：检查 `BRIDGE_TRUSTED_CLIENTS` 是否包含真实 Docker 子网；
- Xboard 路由不存在：核对 `PassportRoute.php` 和 `UserRoute.php`；
- PHP 语法错误：桥接用 PHP 7.4+ 校验，Xboard 文件必须在 Xboard PHP 8.2+ 环境校验；
- SQLite 写入失败：为服务用户配置最小化 owner/group/ACL，不要使用 `chmod 777`；
- Nginx 校验失败：安装器会恢复原配置，查看输出的备份目录；
- 手机端仍显示旧组件：清理页面/CDN缓存后确认资源查询版本已变化。

进一步诊断见 [故障排查](TROUBLESHOOTING.md) 和 [安全说明](SECURITY.md)。
