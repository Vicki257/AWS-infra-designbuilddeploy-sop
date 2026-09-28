# Phase 2　构筑

**目标**：IaC 的每一个值都能追溯到设计书，且实装 = 最终状态定义书。

| Step | 标题 | 担当 |
|---|---|---|
| 2-1 | IaC 模板的生成 | AI |
| 2-2 | 追溯性检查 | AI → 人 |
| 2-3 | 变更集的安全确认 | 人 + AI |
| 2-4 | 构筑执行 | 人 |
| 2-5 | **G3 构筑后 Reconcile** | AI |

---

## Step 2-1　IaC 模板的生成

**担当**：AI　**产出**：CloudFormation 模板

### 手顺

**① 人把以下贴给 AI**

- 确定版环境设计书
- `workspace/FINAL_STATE.md`
- 当前阶段（P1 疎通确认 / P2 / 最终状态）

**② AI 使用 `docs/92-prompts.md` 的 A-4 模板生成**

### 生成规则（AI 必须遵守）

1. **每个资源加追溯注释**
   ```yaml
   # 环境设计书 1.ネットワーク設計 4.セキュリティグループ No.1
   ```

2. **设计书没写的值不许自己决定**
   → 作为「未定义项目」单独列出

3. **满足「（上記以外は存在しないこと）」**
   不要生成多余的资源和规则

4. **暂定设定要打标记**
   ```yaml
   # 暫定：<理由> / 撤去条件：<条件> / 期限：<Gate>
   ```
   并在作业结束时输出暂定台账的追加行

5. **避免会导致资源重建的写法**
   - AMI ID 用**固定值**，不要用 `{{resolve:ssm:...latest}}`
     （更新时会解析到新 AMI，导致实例重建）
   - `UserData` 的变更必然导致 EC2 重建 —— 把会变的配置放在 UserData 外面

6. **栈要分层**
   - 无课金资源（VPC / 子网 / 路由表 / SG / 密钥对）
   - 有课金资源（EC2 / RDS / ALB / 证书 / DNS）
   - 运用（Lambda / 调度 / 告警）

   分开的理由：演习・开发结束时只删有课金的那层，费用归零。

### AI 的输出必须包含

1. 模板本体
2. **未定义项目列表**
3. 暂定设定台账的追加行
4. **这个模板不会创建、但最终状态定义书里有的东西**（= 需要手动作业的部分）

### 验收基准

- [ ] 未定义项目列表为空，或全部已向上位确认
- [ ] 每个资源都有追溯注释
- [ ] 第 4 项（手动作业部分）已明确列出

---

## Step 2-2　追溯性检查

**担当**：AI 检查 → 人处理　**产出**：追溯表

### 手顺

**① AI 使用 `docs/92-prompts.md` 的 A-5 模板**

**② AI 输出**

```
| 资源/属性 | 设定值 | 设计书的根据位置 | 判定 |
```

判定三种：**OK**（设计书明记）/ **推测**（AI 补完的）/ **不明**（找不到根据）

最后单独列出「推测」「不明」的行。

**③ 人逐行处理「推测」「不明」**

> **这一步跳过 = 设计书里没有的值悄悄进了生产配置。**

### 验收基准

- [ ] 「推测」「不明」的行全部处理完（改为有根据的值，或向上位确认后记录为独自决定）

---

## Step 2-3　变更集的安全确认

**担当**：人 + AI　**产出**：变更集的确认结果

> 新规栈创建时跳过 ①〜③，直接到 Step 2-4。既存栈更新时必做。

### 手顺

**① 取现行模板**

> 场所：CloudShell

```
aws cloudformation get-template --region <REGION> --stack-name <栈名> --output json > template-current.json
```

> ⚠️ **必须 `--output json`。**
> `--output text` 会破坏 `LaunchTemplateData` 等嵌套结构，
> 用它取出来的模板再投入会导致 EC2 被判定为需要重建。

**② 创建变更集**

```
aws cloudformation create-change-set --region <REGION> --stack-name <栈名> --change-set-name safety-check --template-body file://template-new.yaml --parameters <参数> --capabilities CAPABILITY_NAMED_IAM
```

**③ 确认内容**

```
aws cloudformation describe-change-set --region <REGION> --stack-name <栈名> --change-set-name safety-check --query 'Changes[].ResourceChange.{Action:Action,Res:LogicalResourceId,Repl:Replacement}' --output table
```

**④ 判定**

| `Replacement` | 判定 |
|---|---|
| 全部 `False` 或空 | **可以执行** |
| 有 `True` 或 `Conditional` | **不可执行**，进 ⑤ |

**⑤ 查明原因**

```
aws cloudformation describe-change-set --region <REGION> --stack-name <栈名> --change-set-name safety-check --query 'Changes[?ResourceChange.Replacement!=`False`].ResourceChange.Details' --output json
```

`Target.RequiresRecreation` 为 `Always` 的属性就是原因。

**⑥ 删除检查用变更集**

```
aws cloudformation delete-change-set --region <REGION> --stack-name <栈名> --change-set-name safety-check
```

> 成功时无输出（正常）。用 `list-change-sets` 确认已消失。

### 验收基准

- [ ] `Replacement` 全部为 `False`，**或**已确认重建是可接受的并已向上位报告
- [ ] 检查用变更集已删除

---

## Step 2-4　构筑执行

**担当**：人　**产出**：栈

### 手顺

按栈的依赖顺序执行（基盘 → 服务器 → 运用）。

每个栈：
1. 控制台 → CloudFormation → **スタックの作成**
2. 模板上传 → 参数输入 → 作成
3. 状态变为 `CREATE_COMPLETE` 后进入下一个栈

**失败时**：`イベント` 标签看第一个 `CREATE_FAILED` 的原因（后面的都是连锁失败）。

### 验收基准

- [ ] 全部栈为 `CREATE_COMPLETE` / `UPDATE_COMPLETE`
- [ ] Outputs 已记录进 `workspace/PROJECT_CONTEXT.md`

---

## Step 2-5　G3　构筑后 Reconcile

**担当**：AI　**产出**：差分一览

### 为什么

**实装 ≠ 设计书**是所有事故的最终形态。定期机械对照。

### 手顺

**① 先跑构成审计**（→ `docs/93-audit.md`）

> 场所：CloudShell

```
bash scripts/audit.sh | tee ~/audit-$(date +%Y%m%d).txt
```

FAIL 全部处理完再往下。

**②'** 取实环境构成

```
bash scripts/inventory.sh > ~/inventory-$(date +%Y%m%d).txt 2>&1
```

**② AI 使用 `docs/92-prompts.md` 的 A-6 模板**

输入：`FINAL_STATE.md` + 实环境输出 + 当前阶段 + `TEMP_SETTINGS.md`

**③ AI 输出三分类**

```
## A. 未实装（设计书有，实环境没有）
## B. 多余（实环境有，设计书找不到根据）
## C. 值不同（两边都有但值不一样）
```

**B 的每一行还要判定**：
- `暂定（台账已登录・期限内）` → OK
- `撤去漏れ` → 要处理
- `暂定（台账未登录）` → **最危险。没有任何人对它的撤去负责**

### 验收基准

- [ ] **`scripts/audit.sh` 的 FAIL 为零**
- [ ] **B 的「台账未登录」为零**
- [ ] B 的「撤去漏れ」为零，或期限已明示
- [ ] C 为零，或已记入 `workspace/DIFF_LOG.md`

---

## Phase 2 完了条件

- [ ] Step 2-1〜2-5 全部验收通过
- [ ] `workspace/STATE.md` 更新为 `Phase 3/4`（Gate 与运用并行）
