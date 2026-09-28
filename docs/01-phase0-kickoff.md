# Phase 0　立项

**目标**：把「后面每一步都要用到的前提」全部固定下来。

| Step | 标题 | 担当 |
|---|---|---|
| 0-1 | 文档体系与优先顺位的确定 | 人 |
| 0-2 | 成本配分标签的启用 | 人 |
| 0-3 | AI 作业环境的准备 | AI → 人确认 |
| 0-4 | 既存环境的台账化 | AI |
| 0-5 | 时间常数表的作成 | AI |

---

## Step 0-1　文档体系与优先顺位的确定

**担当**：人　**产出**：`workspace/PROJECT_CONTEXT.md` 的「文档优先顺位」段

### 为什么

最常见的事故是**两份设计书互相矛盾，构筑抄了下位那份**。
先定「冲突时以哪份为准」，后面 G1 才有判定基准。

### 手顺

**① 列出所有已存在的文档**

| # | 文档名 | 版本 | 最终更新 | 保管场所 |
|---|---|---|---|---|

**② 向上位者确认第 1 顺位是哪份**

确认文（日文・直接可发）：

```
本プロジェクトで、設定値に差異があった場合に
最終的に正とする設計書はどちらでしょうか。

 ・方式設計書
 ・環境設計書

また、環境設計書のテンプレートに記載されているサンプル値は、
そのまま採用してよいものでしょうか。
それとも方式設計書に合わせて見直す必要がありますでしょうか。
```

**③ 把结果写进 `workspace/PROJECT_CONTEXT.md`**

**④ 模板文档的样例值全部标记为「未确认」**

### 验收基准

- [ ] 优先顺位表已填，第 1 顺位的文档已取得
- [ ] 模板的样例值已标记「未确认」
- [ ] `PROJECT_CONTEXT.md` 的该段已填

---

## Step 0-2　成本配分标签的启用

**担当**：人　**产出**：启用完成 or 依赖记录

### 为什么

**这是唯一一个事后完全无法补救的项目。**
成本配分标签**只对启用之后产生的数据生效，不追溯**。
共用账号里没有标签，就永远无法分出本项目的费用。

### 手顺

**① 确认账号是专用还是共用**

> 场所：CloudShell

```
aws sts get-caller-identity
```

专用账号 → 跳过后面，标记本 Step 完成。

**② 确认 Billing 权限**

控制台右上账号名 → **Billing and Cost Management**

打得开 → ③　打不开 → ⑤

**③ 确认标签状态**

**Billing** → 左侧 **Cost allocation tags** → **User-defined cost allocation tags**

目标标签键存在且 **Active** → 完成
不存在 / Inactive → ④

**④ 给资源打标签后启用**

> 场所：CloudShell

```
aws resourcegroupstaggingapi tag-resources --region <REGION> --resource-arn-list <ARN1> <ARN2> --tags Project=<项目标识>
```

回到 ③ 的画面，勾选标签键 → **Activate**

**⑤ 没有权限时，发依赖文**（日文・直接可发）

```
関係者各位

本プロジェクトの AWS 利用費を把握するため、
コスト配分タグの有効化をお願いしたく存じます。

コスト配分タグは有効化した日以降のデータにのみ適用され、
遡及して集計することができないため、早期のご対応をお願いいたします。

 ・対象タグキー：<タグキー>
 ・対象リソース：<プレフィックス> で始まるリソース一式

権限をいただければ当方で設定いたします。
よろしくお願いいたします。
```

### 验收基准

- [ ] 标签为 Active，**或**依赖已发出且记录了发送日

---

## Step 0-3　AI 作业环境的准备

**担当**：AI 生成 → 人确认　**产出**：`workspace/` 下的台账一式

### 手顺

**① 复制模板**

```
cp templates/*.md workspace/
```

**② AI 带着人填 `workspace/PROJECT_CONTEXT.md`**

AI 逐项提问，人回答，AI 输出填好的完整文件。
**不知道的项目留空并标记「未确认」，不要猜。**

**③ 确认 `workspace/AI_RULES.md` 的内容**

这是每次新对话要贴给 AI 的作业规则。原则上不改。

### 验收基准

- [ ] `workspace/` 下有全部台账文件
- [ ] `PROJECT_CONTEXT.md` 的已知项目全部填完
- [ ] 未知项目标记为「未确认」而不是被猜测填入

---

## Step 0-4　既存环境的台账化

**担当**：AI　**产出**：构成一览

> 新建环境时跳过。接手既存环境时必做。

### 手顺

**① 跑构成取得脚本**

> 场所：CloudShell

把 `scripts/inventory.sh` 的内容整段粘贴执行，或：

```
bash scripts/inventory.sh > ~/inventory-$(date +%Y%m%d).txt 2>&1
```

**② 下载**

CloudShell 右上 **Actions** → **Download file** → 输入 `inventory-YYYYMMDD.txt`

**③ AI 把输出整理成台账，填进 `PROJECT_CONTEXT.md`**

### 验收基准

- [ ] 构成一览已取得
- [ ] `PROJECT_CONTEXT.md` 的「接续信息」段已填完

---

## Step 0-5　时间常数表的作成

**担当**：AI　**产出**：`PROJECT_CONTEXT.md` 的时间常数表

### 为什么

变更后**没等满就判定失败**是最常见的误判。
先把数字算出来放手边。

### 手顺

**① 取健康检查的设定**

> 场所：CloudShell

```
aws elbv2 describe-target-groups --region <REGION> --query 'TargetGroups[].{Name:TargetGroupName,Interval:HealthCheckIntervalSeconds,Healthy:HealthyThresholdCount,Unhealthy:UnhealthyThresholdCount}' --output table
```

**② AI 计算并填表**

| 项目 | 值 | 计算式 |
|---|---|---|
| 健康检查间隔 | 秒 | |
| Healthy 阈值 | 回 | |
| **变 Healthy 所需时间** | **秒** | 间隔 × Healthy 阈值 |
| Unhealthy 阈值 | 回 | |
| **变 Unhealthy 所需时间** | **秒** | 间隔 × Unhealthy 阈值 |
| ALB 空闲超时 | 秒 | 默认 60 |

**③ 取调度一览（如果有）**

```
aws events list-rules --region <REGION> --query 'Rules[].{Name:Name,Sched:ScheduleExpression,State:State}' --output table
```

```
aws scheduler list-schedules --region <REGION> --output table
```

```
aws rds describe-db-instances --region <REGION> --query 'DBInstances[].{Id:DBInstanceIdentifier,BackupWin:PreferredBackupWindow,MaintWin:PreferredMaintenanceWindow,BackupDays:BackupRetentionPeriod}' --output table
```

**④ AI 做时间窗交叉验证**

cron 表达式是 **UTC**，全部换算成当地时间后，检查：

| 检查项 | 判定 |
|---|---|
| RDS 备份窗口 ⊂ RDS 运行时间 | **必须成立**。否则备份一次都不会执行 |
| RDS 维护窗口 ⊂ RDS 运行时间 | 必须成立 |
| EC2 启动时刻 ≤ 开局时刻 | 必须成立 |
| 闭局时刻 ≤ EC2 停止时刻 | 必须成立 |
| cron 的月指定 / EndDate 是否会导致停止发火 | 确认 |

NG 的项目 → 不要自己改，写进确认事项书（`docs/90-playbooks.md` P-70）

### 验收基准

- [ ] 时间常数表已填，**变 Healthy 所需时间**已算出
- [ ] 5 个交叉验证项已全部判定
- [ ] NG 项已记入确认事项书

---

## Phase 0 完了条件

- [ ] Step 0-1〜0-5 全部验收通过
- [ ] `workspace/STATE.md` 更新为 `Phase 1 / Step 1-1`
