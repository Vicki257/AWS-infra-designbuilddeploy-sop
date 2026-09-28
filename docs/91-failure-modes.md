# 故障模式速查

按**症状**查。

---

## 1. 流程上的失败

| 症状 | 根因 | 对策 |
|---|---|---|
| 上位者指出「和设计书不符」 | 抄了下位 / 模板文档 | `00-overview.md` 文档优先顺位 / G1 |
| 加了新东西，旧东西没删 | 指示是「加什么」而不是「目标状态」 | `AI_START_HERE.md` 铁则1 / Gate |
| 改了 A，B 坏了但没人发现 | 依赖关系未登记 | Step 1-4 / Phase 4 的 ① |
| 设计书本身写错了 | 未做实在性审查 | G2 |
| 环境重建后配置回退 | 实装变更未回写 | P-60 / Step 5-5 |
| 备份一次都没跑成 | 备份窗口落在停机时段 | Step 0-5 / G6 第6项 |
| 监视设了但没通知 | 只确认了「设定存在」 | Phase 4「监视的健全性验证」 |
| 闭局能被绕过 | EC2 直接暴露 / 监听器遗漏 | G5 第5・12项 |
| **闭局静默失效** | 删监听器时没改 Lambda 的 ARN | G5 的执行顺序 |
| 成本分不出团队 | 标签未启用且不追溯 | Step 0-2 |
| 删完数据后应用报错 | COUNT 基发号撞号 | P-40 Step 4 |

---

## 2. AI 使用上的失败

| 症状 | 根因 | 对策 |
|---|---|---|
| AI 填了设计书里没有的值 | 未指示「没根据的值不许填」 | 铁则2 |
| AI 只加不删 | 指示是「加什么」 | 铁则1 |
| AI 说得很肯定但是错的 | 未要求区分「推测」 | 铁则4 |
| AI 每次都要重新告知前提 | 无 `PROJECT_CONTEXT.md` | Step 0-3 |
| AI 执行了危险操作 | 未要求三件套 | 铁则3 |
| AI 一口气做了好几步，中间出错 | 未限制「一次一个 Step」 | `AI_START_HERE.md` 第3节 |

---

## 3. 技术上的失败

### 3.1 网络・负载均衡

| 症状 | 原因 | 对处 |
|---|---|---|
| 目标组 Unhealthy（刚变更完） | 还在回复窗口内 | 等满「间隔 × Healthy 阈值」 |
| 目标组 Unhealthy（等满了） | 健康检查来源被 SG 封 / 路径非 200 | EC2 上 `curl localhost` 确认 |
| **504 Gateway Time-out** | 安全组是 **drop** 不是 reject，连接挂起 | 见 P-11 前置知识 |
| 503 Service Unavailable | 全部目标 Unhealthy（常见于同时重启全部实例） | 等回复；今后 1 台 1 台做 |
| 502（页面不像 AWS 的） | 企业出口代理的错误页 | 换网络确认 |
| 健康检查协议是 HTTP 看着不对 | ALB→EC2 是内部通信，通常就是 HTTP | 正常 |

### 3.2 Tomcat・部署

| 症状 | 原因 | 对处 |
|---|---|---|
| 部署了但行为没变 | `webapps/ROOT` 目录残留 | `rm -rf` 后重做 + Ctrl+F5 |
| 日志 `Permission denied` | war 的属主是 ec2-user | `chown tomcat:tomcat` |
| 意料外的路径能访问 | `webapps/` 下有多余目录 | 移到 webapps 外 |
| `/manager/html` 能打开 | httpd 的排除规则在一般规则**后面** | `ProxyPass /manager !` 要在 `ProxyPass /` 前 |
| 404 Not Found | war 的名字不是 `ROOT.war` | 确认部署名 |
| 刷新时画面时好时坏 | 多台的 war 不一致 | 对没更新的那台重做 |

### 3.3 CloudFormation

| 症状 | 原因 | 对处 |
|---|---|---|
| 变更集显示 EC2 要重建，但 diff 只有几行 | `--output text` 取模板破坏了嵌套结构 | 改用 `--output json`；或手动变更 + 差分记录 |
| 更新时 EC2 无故重建 | AMI 用了 `{{resolve:ssm:...latest}}`，解析到了新 AMI | AMI 用固定值 |
| `UserData` 一改 EC2 就重建 | 规格如此 | 会变的配置放 UserData 外面 |
| `delete-change-set` 没反应 | 成功时无输出（正常） | `list-change-sets` 确认已消失 |
| 栈创建失败 | 看**第一个** `CREATE_FAILED` | 后面的都是连锁失败 |
| EC2 停止中栈更新失败 | Outputs 引用了 `PublicIp`（停止中不存在） | 从 Outputs 移除 |

### 3.4 数据库

| 症状 | 原因 | 对处 |
|---|---|---|
| `Access denied ... FLUSH TABLES WITH READ LOCK` | `--single-transaction` + 无 RELOAD 权限 | 换 `--skip-lock-tables` |
| `unknown variable 'set-gtid-purged=OFF'` | MariaDB 客户端不支持 | 去掉该选项 |
| CloudShell 连不上 RDS | SG 只允许 EC2 | 到 EC2 上执行 |
| `Cannot delete or update a parent row` | 删除顺序反了 | 子表先删 |
| 表名大小写行为和本地不一样 | `lower_case_table_names` | 只能在实例创建时指定 |

### 3.5 作业环境

| 症状 | 原因 | 对处 |
|---|---|---|
| `ssh: Could not resolve hostname <1.2.3.4>` | 占位符的尖括号没删 | 删掉 `< >` |
| `cd: C:Users...: No such file or directory` | 在 EC2 上跑了 Windows 命令 | 看提示符 |
| `mysqldump: 用語 ... 認識されません` | 在 PowerShell 里跑了 Linux 命令 | 到 EC2 上跑 |
| `rm -rf` 在 CloudShell 没效果 | 在错误的机器上执行 | 看提示符 |
| PowerShell 里反斜杠续行报错 | PowerShell 不支持 `\` 续行 | 写成一整行 |
| 命令打了没反应 | `rm` `cp` 等成功时无输出 | 用 `ls` 确认结果 |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | IP 被重新分配给了别的机器 | `ssh-keygen -R <IP>` |
| `UNPROTECTED PRIVATE KEY FILE` | pem 权限太松 | 属性 → 安全 → 高级 → 禁用继承 |
| 每天 IP 都变 | 无 EIP，停止启动后重新分配 | 每次作业前重取，或申请 EIP |

---

## 4. 用脚本一次查完

上面第 1・3 节的大部分项目，`scripts/audit.sh` 能自动判定：

```
bash scripts/audit.sh | tee ~/audit-$(date +%Y%m%d).txt
```

详见 `docs/93-audit.md`。

**但下面 3 项脚本查不出来，必须人实测**：

| # | 项目 | 为什么查不出来 |
|---|---|---|
| 1 | 闭局是否真的遮断 | API 返回的设定是正常的 |
| 2 | 监视是否真的发火 | 规则存在 ≠ 事件模式匹配 |
| 3 | 告警邮件是否真的到达 | 告警状态正常 ≠ 邮件送达 |

---

## 5. 追加新的失败模式

遇到本表没有的失败，处理完后追加到对应的小节：

```
| 症状（使用者会看到的现象） | 原因（根本原因，不是表面） | 对处（具体动作） |
```

**写「症状」时用使用者实际看到的文字**，不要用推测后的术语。
这张表是按症状查的，症状写得不像，就查不到。
