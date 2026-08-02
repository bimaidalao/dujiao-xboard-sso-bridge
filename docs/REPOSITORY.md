# 成品仓库结构与维护方式

## 唯一入口

部署者只需要记住一个命令：

```bash
sudo /opt/dujiao-xboard-sso-bridge/bin/dx-bridge <command>
```

支持 `install`、`update`、`check`、`rollback`、`validate` 和 `version`。根目录旧脚本仍保留为兼容层，但不再要求用户分别理解它们。

## 分层

- `dujiao/public/`：桥接服务公开入口，只负责认证、账号映射和安全订单摘要；
- `xboard/`：Xboard 控制器与数据库迁移；
- `templates/production/`：可参数化的真实前端资源，不包含真实域名；
- `bin/`：面向部署者的统一命令；
- `lib/`：安装器共享函数和前端安装逻辑；
- `scripts/`：仓库校验和恢复工具；
- `deploy/`：Nginx、systemd 示例；
- `docs/`：架构、部署、安全、故障排查和生产基线。

## 发布标准

每次发布必须：

1. 更新 `VERSION` 和 `CHANGELOG.md`；
2. 执行 `bin/dx-bridge validate`；
3. 在兼容的 Xboard PHP 容器内运行 PHP 语法检查；
4. 使用临时普通账号验证双向登录、独立密码登录和工单订单摘要；
5. 确认 `check` 全部通过后再打 Git 标签。

GitHub Actions 会对 Bash、PHP、JavaScript 和必要文件进行基础校验，阻止明显损坏的版本进入主分支。

## 升级和回滚

`update` 只允许快进更新，工作目录存在未提交修改时停止。安装器每次运行都会在 `/var/backups/dujiao-xboard-sso-bridge/` 建立时间戳备份，并写入路径清单。

```bash
sudo bin/dx-bridge rollback
```

默认只恢复程序与配置，不恢复商城数据库。只有明确传入 `--with-db` 才会恢复数据库快照，避免误覆盖新订单。
