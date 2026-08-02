# 故障排查

## 一键登录后仍回到登录页

- 检查来源 Token 是否过期；
- 检查邮箱是否已验证、账号是否禁用；
- 检查两个内部 API 是否能从服务器本机访问；
- 查看桥接日志，但不要输出 Authorization 或 Token。

## 一边可以登录，另一边密码错误

- 确认已从密码正确的来源站完成一次一键登录；
- 检查两边哈希是否都是 bcrypt，长度通常为 60；
- 检查目标账号是否按同邮箱匹配；
- 检查 password setup 标记、password algo 和 salt 字段是否已清理；
- 修改密码后，需要从修改密码的站点再次发起 SSO 才会同步。

## PHP Composer 版本错误

不要在旧版 PHP 桥接进程中直接加载要求 PHP 8.2 的 Xboard Composer。使用 PDO 最小权限连接读取必要字段，或让桥接服务本身运行兼容的 PHP 版本。

## 容器重启后连接被拒绝

不要只等待容器状态为 Up。应循环请求健康接口，连续三次返回 200 后再执行 SSO 验证。

## Docker 中访问桥接失败

- 先执行 `docker inspect --format '{{.HostConfig.NetworkMode}}' 容器名`；
- host 网络应使用 `127.0.0.1:18081`；
- bridge 网络应使用安装器检测到的 Docker 网关；
- `credential.php` 返回 403 时核对 `/etc/dujiao-xboard-sso-bridge.env` 中的 `BRIDGE_TRUSTED_CLIENTS`；
- 不要把可信网段改成 `0.0.0.0/0`，也不要向公网开放 `18081`。

重新检查：

```bash
sudo /opt/dujiao-xboard-sso-bridge/bin/dx-bridge check
```

## 工单没有订单摘要

- 确认 `/user/ticket/save` 已指向 `StoreOrderTicketController`；
- 确认迁移已经增加 `go_order_id` 和 `go_order_no`；
- 节点订单按当前 Xboard `user_id` 查询，商城订单按映射邮箱查询；
- 某一边确实没有订单时只会附带另一边；
- 检查桥接日志中的 `order verification failed`，但不要输出 Authorization。

## 手机端无法滑动或按钮被遮挡

- 检查悬浮容器是否覆盖全屏；
- 父容器设置 `pointer-events: none`，按钮设置 `pointer-events: auto`；
- 关闭的菜单使用 `display: none`；
- 为底部导航、safe-area 和“回到顶部”按钮预留高度。

## 浏览器仍显示旧样式

更新 CSS/JS 查询版本号，清理 CDN 缓存，并在手机浏览器强制刷新。
