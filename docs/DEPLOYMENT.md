# 部署

## 1. Xboard 端

复制 `xboard/GoSsoController.php`，并将命名空间、User 模型与登录服务调整到当前 Xboard 版本。添加 `routes.php.snippet` 中的 POST 路由。

设置环境变量：

```dotenv
DUJIAO_IDENTITY_URL=http://127.0.0.1:18080/api/v1/me
DUJIAO_SSO_FAILURE_URL=https://store.example.com/auth/login?sso=failed
```

## 2. Dujiao Next 端

将 `dujiao/public/index.php` 放入独立目录，通过 PHP-FPM 或仅监听本机的 PHP 服务运行。设置 `.env.example` 中对应变量。

## 3. Web 服务器

参考 `deploy/nginx.conf.example`，只把固定 SSO 路径代理到内部桥接服务。建议增加每 IP 限流和 16 KiB 请求体上限。

## 4. 前端入口

先加载 `frontend/config.example.js`，再在商城加载 `frontend/dujiao-entry.js`，在 Xboard 加载 `frontend/xboard-entry.js`。

## 5. 验证

- 未登录用户点击入口后应进入本站登录页。
- 已登录且邮箱已验证的用户可双向跳转。
- 被禁用用户无法跳转。
- 非白名单 redirect 值应回到默认页面。
- 响应不得缓存，浏览器历史中不得出现 Token URL。

