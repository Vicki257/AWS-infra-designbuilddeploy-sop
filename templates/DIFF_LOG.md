# 差分一览（设计书/模板 与 实环境的不一致）

> IaC 无法更新时，**手动变更必须记录**。
> 记录漏掉 = 环境重建时静默回退。

最终更新：YYYY/MM/DD

| # | 项目 | 设计书/模板的值 | 实环境的值 | 变更日 | 变更理由 | 重建时的再适用手顺 |
|---|---|---|---|---|---|---|
| 1 | | | | | | |

---

## ⚠️ 警告文（交付时必须写进文档开头）

```
環境を再構築した場合、UserData等により設定が初期値に戻ります。
再構築時は本書「差分一覧」の再適用手順を必ず実施してください。
```

---

## 漂移检测

**变更之后**重新取。变更前的 `IN_SYNC` 不是证据。

```
aws cloudformation detect-stack-drift --region <REGION> --stack-name <栈名>
```

```
aws cloudformation describe-stack-resource-drifts --region <REGION> --stack-name <栈名> --stack-resource-drift-status-filters MODIFIED DELETED --query 'StackResourceDrifts[].{Res:LogicalResourceId,Status:StackResourceDriftStatus}' --output table
```

| 检测日 | 结果 | 备注 |
|---|---|---|
