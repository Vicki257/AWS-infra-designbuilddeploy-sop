# 依赖关系登记

> **改一个值之前，先查这张表。**
>
> 「改了 A，依赖 A 的 B 没人回头查」是第二常见的事故。
> 典型：运行时间改了但备份窗口没改 → 备份永远落在停机时段，**一次都没执行过，且不报错**。

| # | 变更的值 | 受影响的值 | 理由 | 确认方法 |
|---|---|---|---|---|
| 1 | RDS 停止时刻 | PreferredBackupWindow | 停止中不执行备份 | `describe-db-instances` |
| 2 | RDS 停止时刻 | PreferredMaintenanceWindow | 同上 | 同上 |
| 3 | 运行调度 | 告警的 TreatMissingData | 停止中指标缺损会误报 | `describe-alarms` |
| 4 | 证书取得 | ALB 监听器构成 | HTTPS 追加・HTTP 撤去 | `describe-listeners` |
| 5 | 证书取得 | ELB SG 的入站 | 80 变得不需要 | `describe-security-groups` |
| 6 | 证书取得 | **开闭局处理的对象 ARN** | 监听器换了，Lambda 要跟着换 | Lambda 的环境变量 |
| 7 | 公开路径 | 健康检查路径 | | `describe-target-groups` |
| 8 | 公开路径 | 反向代理设定（httpd） | | EC2 上确认配置文件 |
| 9 | 公开路径 | Outputs 的 URL | | `describe-stacks` |
| 10 | 实例类型 | 成本试算 | | |

> 上面 10 行是最低限。项目固有的依赖用 `docs/92-prompts.md` 的 **A-3** 抽出后追加。
> 不适用的行写「不适用」，不要直接删掉 —— 留着能证明已经检查过了。

## 项目固有的依赖

| # | 变更的值 | 受影响的值 | 理由 | 确认方法 |
|---|---|---|---|---|
