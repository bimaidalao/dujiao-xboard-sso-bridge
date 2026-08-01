# Dujiao Next ↔ Xboard 双向 SSO Bridge

一个将 Dujiao Next 商城与 Xboard 用户中心连接起来的轻量集成项目。用户只需登录一次，即可在商城和订阅面板之间安全跳转；首次跳转时会按已验证邮箱自动创建对应账号。

## 功能

- Dujiao Next → Xboard 单点登录
- Xboard → Dujiao Next 单点登录
- 按已验证邮箱关联账号
- 自动创建缺失的对应账号
- 跳转目标白名单，防止开放重定向
- 桌面端与手机端跨站入口示例
- 不同步密码，不在浏览器中保存新的共享密钥

## 仓库结构

```text
dujiao/                 Xboard → Dujiao 的服务端桥接
xboard/                 Dujiao → Xboard 的 Laravel 控制器与路由示例
frontend/               两个站点的入口组件
deploy/                 Nginx 与 systemd 示例
docs/                   安全与部署说明
```

## 安全边界

本项目只同步身份，不同步密码、订单交付内容、卡密或支付数据。生产环境必须启用 HTTPS，内部身份接口应只允许本机或私有网络访问。

仓库不包含任何真实域名、服务器 IP、SSH 私钥、JWT 密钥、数据库或用户数据。请从 `.env.example` 创建自己的运行配置。

## 快速接入

1. 将 `xboard/GoSsoController.php` 放入 Xboard 对应控制器目录，并按 `xboard/routes.php.snippet` 添加路由。
2. 将 `dujiao/public/index.php` 部署为仅处理 `POST` 的内部桥接服务。
3. 参考 `deploy/nginx.conf.example` 暴露桥接入口。
4. 在两个前端页面加载 `frontend/config.example.js` 以及对应入口脚本。
5. 逐项检查 `docs/SECURITY.md` 后再投入生产。

详细参数和验证步骤见 [部署文档](docs/DEPLOYMENT.md)。

## 兼容性

这是适配示例，不修改两个上游项目的核心认证模型。不同版本的 Dujiao Next 或 Xboard 可能需要调整用户字段、路由命名及 API 响应结构。

## License

MIT

