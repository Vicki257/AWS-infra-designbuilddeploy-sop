# Phase 3　状态迁移（Gate）

**Gate = 状态迁移的节点。**「加了新东西」不是终点，「旧东西该不该留」才是。

到达 Gate 条件时执行本章对应的 Gate。**和 Phase 4（运用）并行。**

---

## Gate 的通用执行方式

**Step ⓪**　**先跑构成审计**（→ `docs/93-audit.md`）

> 场所：CloudShell

```
bash scripts/audit.sh | tee ~/audit-$(date +%Y%m%d).txt
```

`FAIL` 有的话先处理完再进 Step ①。
`WARN` 对照 `workspace/TEMP_SETTINGS.md` —— **台账里没有的 WARN 按 FAIL 处理**。

**Step ①**　取实环境构成

> 场所：CloudShell

```
bash scripts/inventory.sh > ~/inventory-$(date +%Y%m%d).txt 2>&1
```

**Step ②**　AI 使用 `docs/92-prompts.md` 的 A-7 模板，对照清单判定

```
| # | 项目 | 期待值 | 实际值 | 合否 | 不合时的对应手顺 |
```

**Step ③**　「否」的项目，AI 先出**三件套**（方案・影响・复旧），人批准后执行

**Step ④**　全部「合」后，记录到 `workspace/GATE_LOG.md`

---

## G4　域名取得・DNS 设定完了

| # | 项目 | 确认方法 | 期待值 |
|---|---|---|---|
| 1 | DNS 记录已指向 ALB | `dig <域名>` 或 `nslookup` | 返回 ALB 的 IP |
| 2 | 手顺书里的临时 URL 已替换为正式域名 | 全文检索 ALB 的 DNS 名 | 无残留 |
| 3 | Outputs 的 URL 已更新 | `describe-stacks` | 正式域名 |

---

## G5　证书取得・HTTPS 化完了

> **这是最容易漏的 Gate。**

### ⚠️ 执行顺序（顺序错了会静默坏掉）

如果开闭局（服务时间外遮断）是用「切换 ALB 监听器的默认动作」实现的：

```
1. 先把 Lambda 的 LISTENER_ARN 改成 HTTPS 监听器的 ARN
2. 手动执行 Lambda（mode=close / mode=open）确认动作正常
3. 再删除 HTTP:80 监听器
```

**反过来做，Lambda 会指向已删除的监听器 → 开闭局完全失效，而且不报错。**

### 清单

| # | 项目 | 确认方法 | 期待值 |
|---|---|---|---|
| 1 | **开闭局的对象 ARN 已改为 HTTPS** | Lambda 的环境变量 | HTTPS 监听器的 ARN |
| 2 | **开闭局的动作已实测** | 手动执行 Lambda `{"mode":"close"}` / `{"mode":"open"}` | 都正常切换 |
| 3 | HTTP:80 监听器已删除 | `aws elbv2 describe-listeners --load-balancer-arn <ARN>` | 只有 443 |
| 4 | ELB SG 的 80 已删除 | `aws ec2 describe-security-groups --group-ids <ELB_SG>` | 只有 443 |
| 5 | **EC2 SG 的 80 来源已改为 ELB SG** | 同上（EC2_SG） | 来源是 SG，不是 `0.0.0.0/0` |
| 6 | SSH 22 的公开范围已收紧 | 同上 | 限定 IP，或已改用 SSM |
| 7 | 健康检查的协议・路径 | `aws elbv2 describe-target-groups` | 与设计书一致 |
| 8 | HTTP→HTTPS 重定向的要否 | 向上位确认 | 判断已记录 |
| 9 | Outputs 的 URL | `describe-stacks` | `https://` |
| 10 | 手顺书里的 `http://` | 全文检索 | 无残留 |
| 11 | 证书的有效期限 | `aws acm describe-certificate --certificate-arn <ARN> --query 'Certificate.NotAfter'` | 已登记日历 |
| 12 | **闭局的实测** | 见下 | 3 个入口全部被遮断 |

### 第 12 项的验证手顺

闭局时间带执行：

```
curl -I https://<域名>/
```
```
curl -I http://<域名>/
```
```
curl -I http://<EC2的公网IP>/
```

**期待：3 个全部返回闭局画面或连接被拒。**

> 第 3 个之所以要测：EC2 SG 如果还开着 `0.0.0.0/0`，
> 直接访问 EC2 就绕过了 ALB，**闭局完全无效**。

### 验收基准

- [ ] 12 项全部「合」
- [ ] **`scripts/audit.sh` 的 FAIL 为零**（特别是「開閉局の参照先」「HTTP:80 リスナー残存」）
- [ ] `TEMP_SETTINGS.md` 里期限为 G5 的行全部标记为已撤去
- [ ] G3 Reconcile 重跑一次，B 为零

---

## G6　构筑完了 → IT 开始

| # | 项目 | 确认方法 | 期待值 |
|---|---|---|---|
| 1 | 调试用的 SG 开放已撤去 | Reconcile 的 B | 零 |
| 2 | 健康检查用的临时内容已替换为正式应用 | 实际访问 | 正式画面 |
| 3 | 中间件同捆的管理应用已遮断 | 访问 `/manager/html` `/docs/` | 404 |
| 4 | `webapps/` 下的多余目录已移出 | `sudo ls -l <CATALINA>/webapps` | 只有正式应用 |
| 5 | **监视已实测会发火** | 见 `05-phase4-operate.md` 的「监视的健全性验证」 | 4 项全部 OK |
| 6 | **备份已实际执行过** | `aws rds describe-db-snapshots --db-instance-identifier <ID> --snapshot-type automated` | 有自动快照记录 |
| 7 | `TEMP_SETTINGS.md` 里期限为 G6 的行全部撤去 | 台账 | 全部已撤去 |
| 8 | **`scripts/audit.sh` 的 FAIL 为零** | `bash scripts/audit.sh` | FAIL: 0 |

> **第 6 项**：「设定了保留期 7 天」≠「备份在执行」。
> 备份窗口落在 RDS 停止的时间带时，**一次都不会执行，而且不报错**。
> 必须看实际的快照记录。

---

## G7　IT 完了 → UAT

| # | 项目 | 手顺 |
|---|---|---|
| 1 | 暂定设定的全撤去 | `TEMP_SETTINGS.md` 的 AI 检查（A-9） |
| 2 | Reconcile 的 B・C 为零 | G3 |
| 3 | 整理成可演示的最小数据集 | `90-playbooks.md` P-40 |
| 4 | 运用手顺书的最新化 | |
| 5 | 成本实绩的算出 | `90-playbooks.md` P-50 |

---

## G8　UAT 完了 → 交付

→ `06-phase5-delivery.md`
