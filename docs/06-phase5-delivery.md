# Phase 5　交付

| Step | 标题 | 担当 |
|---|---|---|
| 5-0 | **构成审计（P-80）** | **AI + 人** |
| 5-1 | 交付时数据状态的确认 | 人 |
| 5-2 | 备份取得 | 人 |
| 5-3 | 数据整理 | 人（AI 生成 SQL） |
| 5-4 | 成本算出 | AI |
| 5-5 | 文档最终化 | AI → 人 |
| 5-6 | 最终 Reconcile | AI |

---

## Step 5-0　构成审计（P-80）

**担当**：AI + 人　**产出**：审计报告 + FAIL/WARN 的处理记录

→ 详见 `docs/93-audit.md`

### 手顺

**① CloudShell 上执行**

```
bash scripts/audit.sh | tee ~/audit-$(date +%Y%m%d).txt
```

**② 处理第 1 部的 FAIL / WARN**

| 判定 | 处理 |
|---|---|
| **FAIL** | 逐条出三件套处理 |
| **WARN** | 对照 `TEMP_SETTINGS.md`。**台账里没有的按 FAIL 处理** |

**③ 第 2 部交给 AI**（Prompt **A-11**）对照最终状态定义书

**④ 脚本检不出来的 3 项，人去实测**

| # | 项目 | 方法 |
|---|---|---|
| 1 | 闭局是否真的遮断 | 闭局时间带 `curl` 3 个入口 |
| 2 | 监视是否真的发火 | 人为制造事件看 4 个指标 |
| 3 | 告警邮件是否真的到达 | 临时下调阈值确认收信 |

### 验收基准

- [ ] FAIL 为零
- [ ] WARN 全部在 `TEMP_SETTINGS.md` 里，或已处理
- [ ] 第 2 部的对照结果，差分为零或已记入 `DIFF_LOG.md`
- [ ] 上表 3 项实测完成

---

## Step 5-1　交付时数据状态的确认

**担当**：人

**自己不要决定。** 确认文（日文・直接可发）：

```
納品にあたり、DB内のデータをどこまで整理すべきかご教示ください。

 ① 初期データ投入直後の状態に戻す
 ② テストで追加した分のみ削除し、初期データは残す
 ③ 特に整理は不要
 ④ マスタ系以外の履歴系データは0行にする

なお、マスタ系（ログイン情報・各種コードマスタ）は変更しない想定です。
作業前に必ずバックアップを取得いたします。

よろしくお願いいたします。
```

### 验收基准
- [ ] 回答已取得并记录

---

## Step 5-2　备份取得

→ `90-playbooks.md` **P-10**

**没有备份不许进行 Step 5-3。**

---

## Step 5-3　数据整理

→ `90-playbooks.md` **P-40**

### ⚠️ 删除前必须确认发号逻辑

```sql
-- 危险：COUNT 基。部分删除后会和既存编号撞号
SELECT COUNT(*) + 1 FROM <表>;
SELECT COUNT(<列>) FROM <表>;

-- 安全：MAX 基
SELECT IFNULL(MAX(<列>), 0) + 1 FROM <表>;
```

| 情况 | 对策 |
|---|---|
| MAX 基 | 部分删除 OK |
| **COUNT 基** | **只能全部删除，从 0 件重新发号**。部分删除会产生重复编号导致应用故障 |

确认重复：

```sql
SELECT <编号列>, COUNT(*) FROM <表> WHERE <编号列> IS NOT NULL GROUP BY <编号列> HAVING COUNT(*) > 1;
```

---

## Step 5-4　成本算出

→ `90-playbooks.md` **P-50**

### 路线选择

| 条件 | 路线 |
|---|---|
| 专用账号 | A（Cost Explorer） |
| 共用账号 + 标签已启用 | A（加标签过滤） |
| **共用账号 + 标签未启用** | **B（手算）** + 向管理者依赖 |

> Phase 0 的 Step 0-2 做了的话就是 A。没做就只能 B。

---

## Step 5-5　文档最终化

**担当**：AI 起草 → 人确定

### 为什么

**实装变更没回写文档 = 环境重建时全部回退。**

典型：健康检查路径运用中改了，设计书没更新 →
重建时 UserData 把配置恢复成旧值 → URL 404。

### 手顺

**① `workspace/DIFF_LOG.md` 的最终确认**

```
| # | 项目 | 设计书/模板的值 | 实环境的值 | 变更日 | 变更理由 | 重建时的再适用手顺 |
```

**② 文档开头加警告**

```
⚠️ 環境を再構築した場合、UserData等により設定が初期値に戻ります。
   再構築時は「差分一覧」の再適用手順を必ず実施してください。
```

**③ 可能的话更新设计书本身。不更新时记录理由。**

**④ 漂移检测在变更后重新取**

> 场所：CloudShell

```
aws cloudformation detect-stack-drift --region <REGION> --stack-name <栈名>
```

```
aws cloudformation describe-stack-resource-drifts --region <REGION> --stack-name <栈名> --stack-resource-drift-status-filters MODIFIED DELETED --query 'StackResourceDrifts[].{Res:LogicalResourceId,Status:StackResourceDriftStatus}' --output table
```

> **变更前取的 `IN_SYNC` 不是证据。**

---

## Step 5-6　最终 Reconcile

**担当**：AI

→ `03-phase2-build.md` 的 **G3** 同样手顺

### 验收基准

- [ ] A（未实装）为零
- [ ] B（多余）为零
- [ ] C（值不同）为零，或全部已记入 `DIFF_LOG.md` 并有再适用手顺

---

## G8 最终清单

| # | 项目 | 确认方法 |
|---|---|---|
| 1 | 交付时数据状态已向上位确认 | 文书 |
| 2 | 备份已取得并验证 | 文件大小・head 确认 |
| 3 | 历史系数据为定义的件数 | COUNT 查询 |
| 4 | 主数据无损伤 | 件数与整理前一致 |
| 5 | Reconcile 全部为零 | Step 5-6 |
| 6 | `DIFF_LOG.md` 最新且有再适用手顺 | 目视 |
| 7 | 监视已实测会发火 | Phase 4 的验证记录 |
| 8 | 备份已实际执行过 | `describe-db-snapshots` |
| 9 | 全文档的版本・日期最新 | 目视 |
| 10 | 提交物里没有真实 IP / 端点 / 密码 | 全文检索 |
| 11 | **`scripts/audit.sh` 的 FAIL 为零** | Step 5-0 |

---

## 项目结束后：SOP 的维护

**Step 1**　列出这次发生的全部「上位者指摘」「事后才发现的问题」

**Step 2**　逐条分类

| 判断 | 处理 |
|---|---|
| SOP 里有，但没照做 | 不改 SOP，改执行纪律 |
| SOP 里有，但步骤不够精确 | 补精确 |
| SOP 里没有，是新的失败类型 | 追加到 `91-failure-modes.md` + 对应机制 |
| 需要新的 Gate | `04-phase3-gates.md` 追加 |
| Prompt 模板没抓住 | 改模板，在 `92-prompts.md` 记录修改理由 |

**Step 3**　更新版本号与更新履历

**Step 4**　发布前检查
- [ ] 无具体项目名・人名・公司名
- [ ] 无真实 IP・域名・端点・密码
- [ ] 占位符统一为 `<...>`
