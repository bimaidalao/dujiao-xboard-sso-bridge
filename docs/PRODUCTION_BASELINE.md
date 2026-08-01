# 生产服务器基线

本项目的一键部署前端不是重新绘制的示意组件，而是从 **2026-08-02 正在运行的生产服务器**提取后参数化的版本。

## 已核对的线上资源

| 组件 | 线上 SHA-256 |
| --- | --- |
| 商城入口 JavaScript | `6b57d54f64b3f7709c2cb6d6d652cc65f979c9b1ab53b9098aca4b4a2dc54104` |
| 商城入口 CSS | `3c0fba58eaecafe774089c24152103e237dda4646fa152aa98ee46c2da55cc82` |
| 节点商店卡片 JavaScript | `37c28391dbe270acfd228469e3d8be422c6f83e3d1ccbab68926772ca0811d0b` |
| 节点商店卡片 CSS | `0b5ccb3e5126306fa7fb8ac28ad4df8213aad153325d8282ade5265fba9abe86` |

仓库模板只替换了以下部署变量：

- 商城和节点公开地址；
- 两个 SSO 地址；
- Telegram 客服链接与用户名；
- 两个 Logo 的安装路径。

把模板变量还原为生产值后，四个文本资源的 SHA-256 与线上文件完全一致。

## 线上功能基线

商城端：

- 桌面端右下角节点入口、工单客服、Telegram 客服；
- 手机端紧凑节点入口；
- 手机客服折叠到底部导航；
- 登录页醒目的注册入口；
- 自动跳转到 Xboard 仪表盘或工单页面。

节点端：

- 桌面端右下角 AI 工具/账号商店卡片；
- 手机端 `186 × 50px` 左右的紧凑卡片；
- 桌面工单与 Telegram 悬浮按钮；
- 手机客服折叠到底部导航；
- 自动提交当前 `auth_data` 进入商城。

认证端：

- Dujiao → Xboard 使用 `go_token`；
- Xboard 路由为 `/api/v1/passport/auth/goSso`；
- Xboard → Dujiao 使用 `xboard_auth` 和 `/sso/xboard`；
- 同邮箱自动创建/匹配；
- bcrypt 哈希双向同步；
- 旧账号以最后发起 SSO 的一侧密码为准。

## 截图生成

README 的四张图片由 `tools/capture-live-screenshots.mjs` 使用线上页面和线上样式生成。节点卡片截图使用无账号文档模式注入与生产脚本相同的 DOM，避免在仓库或截图中保存真实账号、Cookie、Token 和邮箱。

本地刷新截图示例：

```powershell
$env:STORE_URL='https://store.example.com/'
$env:PANEL_URL='https://panel.example.com/#/shop'
$env:CHROME_PATH='C:\Program Files\Google\Chrome\Application\chrome.exe'
node tools\capture-live-screenshots.mjs
```

