# AWS 基础设施　AI 协作开发 SOP

一套让 **AI 带着你一步步建成 AWS 环境**的作业手顺集。

适用对象：Web 三层环境（Route53 / ACM / ALB / EC2×N / RDS + Apache + Tomcat）的
立项 → 设计 → 构筑 → 运用 → 交付。

---

## 怎么用

### 1. 把这个仓库给 AI

新开一个对话，发这句：

```
读取这个仓库并按照 AI_START_HERE.md 的规则带我作业。
<仓库URL 或 把 AI_START_HERE.md 的内容贴上>
```

AI 会自己读 `AI_START_HERE.md`，从里面得到全部行动规则，然后问你当前进度、开始带你做。

### 2. 第一次使用

```
cp templates/*.md workspace/
```

然后把 `workspace/STATE.md` 的「项目名」填上，其他留空。AI 会带你一格一格填。

### 3. 之后每次

新对话时只要发：

```
读取这个仓库，按 AI_START_HERE.md 作业。
当前状态：<把 workspace/STATE.md 贴上>
```

AI 就能接着上次的进度继续。

---

## 仓库结构

```
├── AI_START_HERE.md          ← AI 最先读这个。全部行动规则
├── docs/
│   ├── 00-overview.md        全体流程・Gate 一览・时间常数
│   ├── 01-phase0-kickoff.md  阶段0 立项
│   ├── 02-phase1-design.md   阶段1 设计
│   ├── 03-phase2-build.md    阶段2 构筑
│   ├── 04-phase3-gates.md    阶段3 状态迁移（Gate）
│   ├── 05-phase4-operate.md  阶段4 运用
│   ├── 06-phase5-delivery.md 阶段5 交付
│   ├── 90-playbooks.md       作业手顺（P-xx）
│   ├── 91-failure-modes.md   故障模式速查
│   ├── 92-prompts.md         Prompt 模板集
│   └── 93-audit.md           P-80 最终审计（和设计不符的检出）
├── templates/                空白台账（复制到 workspace/ 使用）
├── scripts/
│   ├── inventory.sh          构成一览取得
│   └── audit.sh              构成审计（PASS/WARN/FAIL 判定）
└── workspace/                你的项目实际文件放这里
```

---

## 这套 SOP 要解决的四类事故

| # | 事故 | 机制 |
|---|---|---|
| A | **两份设计书互相矛盾，构筑抄了错的那份** | G1 文档间一致性检查 |
| B | **改了 A，依赖 A 的 B 没人回头查** | 依赖关系登记 |
| C | **设计书本身写错了（不存在的版本号等）** | G2 实在性审查 |
| D | **"加了新的，旧的没删"** | 最终状态定义 + Gate 撤去清单 |

D 是最常见的。典型例：取得证书上了 HTTPS，但 HTTP:80 监听器、ELB SG 的 80、
EC2 SG 的 `0.0.0.0/0` 全都留着 —— 因为**没有任何一份文档写"要删什么"**。

---

## 最后一道关卡：构成审计

在 CloudShell 上跑一条命令，机械地找出「和设计不符的地方」：

```
bash scripts/audit.sh | tee ~/audit-$(date +%Y%m%d).txt
```

`PASS` / `WARN` / `FAIL` 三级判定。详见 `docs/93-audit.md`。

**每个 Gate、IT 开始前、交付前**各跑一次。人的目视会漏，脚本不会。

对策的核心一句话：

> 给 AI 的指示要问「**目标状态是什么**」，不能问「**要加什么**」。
> 并且强制 AI 输出「**③ 删除**」这一栏，空的时候要说明理由。
