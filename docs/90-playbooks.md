# 作业手顺书（Playbooks）

每个 Playbook 固定 6 段：**何时使用 / 前提确认 / 执行步骤 / 验证 / 回滚 / 失败模式**

占位符对照表在 `workspace/PROJECT_CONTEXT.md`。替换时**要删掉尖括号**。

---

## P-10　数据库备份取得

### 何时使用
删除数据前、大规模变更前、交付前。**任何破坏性操作之前。**

### 前提确认
- [ ] 能 SSH 进 EC2
- [ ] 知道 DB 用户名和密码
- [ ] RDS 正在运行

### 执行步骤

**Step 1**　SSH 进 EC2

> 场所：本机 PowerShell
> ⚠️ **不要在 CloudShell 做** —— CloudShell 连不上 RDS（SG 只允许 EC2）

```
ssh -i <KEY> ec2-user@<EC2_1>
```

**Step 2**　确认 mysqldump 存在

> 场所：EC2

```
which mysqldump
```

没有的话：

```
sudo dnf install -y mariadb105
```

**Step 3**　取备份（**一整行**）

```
mysqldump -h <RDS_EP> -u <DB_USER> -p --no-tablespaces --skip-lock-tables <DB_NAME> > ~/backup_$(date +%Y%m%d_%H%M).sql
```

> ⚠️ **不要加 `--single-transaction`**
> RDS 的 master 用户没有 RELOAD 权限，会因 `FLUSH TABLES WITH READ LOCK` 失败
> ⚠️ **不要加 `--set-gtid-purged=OFF`**
> MariaDB 版的 mysqldump 不认识这个选项

**Step 4**　确认文件不是空的

```
ls -lh ~/backup_*.sql
```

```
head -20 ~/backup_*.sql
```

期待：有相应大小，开头是 `-- MySQL dump` 或 `-- MariaDB dump`

**Step 5**　拉到本机保存

```
exit
```

> 场所：本机 PowerShell

```
scp -i <KEY> ec2-user@<EC2_1>:~/backup_*.sql C:\<保存目录>\
```

### 验证
- [ ] 本机上有备份文件，大小合理
- [ ] 开头是 dump 的头部

### 回滚（从备份恢复）

```
mysql -h <RDS_EP> -u <DB_USER> -p <DB_NAME> < ~/backup_YYYYMMDD_HHMM.sql
```

### 失败模式
| 症状 | 原因 | 对处 |
|---|---|---|
| `Access denied ... FLUSH TABLES WITH READ LOCK` | 用了 `--single-transaction` 但无 RELOAD 权限 | 换成 `--skip-lock-tables` |
| `unknown variable 'set-gtid-purged=OFF'` | MariaDB 客户端不支持 | 去掉这个选项 |
| `mysqldump: command not found`（PowerShell 里） | 在本机执行了 | 到 EC2 上执行 |
| 连接超时 | 在 CloudShell 执行了 | 到 EC2 上执行 |
| 文件 0 字节 | 连接失败但重定向已建文件 | 看错误信息重做 |

---

## P-11　安全组变更

### 何时使用
公开范围收紧、异常测试、新增访问源

### 前提确认
- [ ] 三件套已写
- [ ] 现状截图已取
- [ ] 时间常数已知

### 重要前置知识

> **安全组是 drop，不是 reject。**

删掉规则后，连接不会立刻报错，而是**一直挂起**直到某个超时。

| 路径 | 表现 |
|---|---|
| 浏览器 → ALB → EC2（EC2 端口被封） | ALB 空闲超时 60 秒 → **504 Gateway Time-out** |
| 应用 → RDS（3306 被封） | JDBC 挂起 → ALB 超时 → **504**（不是应用的错误画面） |

**所以：想让应用返回自己的错误画面，不能用安全组。** 见 P-30。

### 执行步骤

**Step 1**　取现状

控制台 → **EC2** → **セキュリティグループ** → 选择目标 → **インバウンドルール** タブ → **截图**

> 场所：CloudShell

```
aws ec2 describe-security-groups --region <REGION> --group-ids <SG_ID> --query 'SecurityGroups[0].IpPermissions' --output json > sg-before.json
```

**Step 2**　变更

**インバウンドのルールを編集** → 修改 → **ルールを保存**

推荐的收紧方式：
- EC2 的 HTTP/HTTPS：来源改为 **ELB 的安全组**（不是 `0.0.0.0/0`）
- RDS 的 3306：来源是 **EC2 的安全组**
- SSH 22：限定到特定 IP，或改用 SSM Session Manager 后关闭

> 来源指定为安全组时：**カスタム** → 输入 `sg-xxxxx` → 从候补里选

**Step 3**　**等满时间常数**（典型 150 秒）

> ⚠️ 这期间目标显示 Unhealthy 是正常的。**不要回滚。**

**Step 4**　验证

```
aws elbv2 describe-target-health --region <REGION> --target-group-arn <TG_ARN> --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' --output table
```

期待：全部 `healthy`

**Step 5**　从浏览器实际访问确认

**Step 6**　记入 `workspace/DIFF_LOG.md`

### 回滚
按 Step 1 的截图恢复规则

### 失败模式
| 症状 | 原因 | 对处 |
|---|---|---|
| 变更后全部 Unhealthy | 还在回复窗口内 | 等满时间常数 |
| 等满了还 Unhealthy，Reason `Request timed out` | 健康检查的来源被封了 | 确认 ELB SG → EC2 SG 允许健康检查端口 |
| 出 504 而不是应用错误页 | SG 是 drop | 规格如此，见前置知识 |

---

## P-12　目标组健康检查变更

### 执行步骤

**Step 1**　取现状截图
控制台 → **EC2** → **ターゲットグループ** → **ヘルスチェック** タブ → **編集**

**Step 2**　确认新路径**不需要认证和会话**就返回 200

> 场所：EC2

```
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080<新路径>
```

期待：`200`。不是 200 就先修应用或换路径。

**Step 3**　变更路径 → **変更を保存**

**Step 4**　**等满时间常数**

**Step 5**　确认全部 `healthy`

**Step 6**　记入 `DIFF_LOG.md`

### 失败模式
| 症状 | 原因 | 对处 |
|---|---|---|
| 协议是 HTTP 看着不对 | ALB→EC2 是内部通信，通常就是 HTTP | 正常 |
| 路径改了一直 Unhealthy | 该路径返回 302 / 401 | 换无认证返回 200 的路径 |

---

## P-20　应用部署（war → Tomcat ×N 台）

### 前提确认
- [ ] 代码已合并到发布分支
- [ ] 本地在发布分支且最新
- [ ] **2 台的当前 IP 已确认**（EC2 重启过 IP 会变）

### 执行步骤

**Step 1**　切分支并拉取

> 场所：本机 PowerShell

```
cd <项目目录>
```
```
git checkout <发布分支>
```
```
git pull
```

**Step 2**　构建

```
mvn clean package
```

期待：`BUILD SUCCESS`

> `Failed to delete target` → 有终端或编辑器占着 `target` 目录，关掉再试

**Step 3**　**确认产物是刚构建的**

```
dir target\<WAR>
```

> 产物文件名每次都一样（来自 `pom.xml`），**只能靠时间戳判断新旧**

**Step 4**　确认测试资源没混进 war

```
jar tf target\<WAR> | Select-String "Test"
```

期待：无输出

**Step 5**　上传到 2 台

```
cd target
```
```
scp -i <KEY> .\<WAR> ec2-user@<EC2_1>:/home/ec2-user/
```
```
scp -i <KEY> .\<WAR> ec2-user@<EC2_2>:/home/ec2-user/
```

期待：显示 `100%`

**Step 6**　部署第 1 台

```
ssh -i <KEY> ec2-user@<EC2_1>
```

> 场所：EC2　部署前先备份现行 war：

```
sudo cp <CATALINA>/webapps/ROOT.war ~/ROOT.war.bak.$(date +%Y%m%d_%H%M)
```

```
sudo systemctl stop tomcat
sudo rm -rf <CATALINA>/webapps/ROOT <CATALINA>/webapps/ROOT.war
sudo cp ~/<WAR> <CATALINA>/webapps/ROOT.war
sudo chown tomcat:tomcat <CATALINA>/webapps/ROOT.war
sudo systemctl start tomcat
sleep 20 && sudo tail -30 <CATALINA>/logs/catalina.out
```

各行的作用：

| 行 | 省略会怎样 |
|---|---|
| `rm -rf .../ROOT` | 旧的解压目录残留，继续用旧文件 |
| `chown tomcat:tomcat` | scp 上来的属主是 ec2-user，Tomcat 读不了 |
| `tail catalina.out` | 启动失败也不知道 |

期待：`Server startup in [xxxx] milliseconds`

**Step 7**　`exit`

**Step 8**　**等满时间常数**，确认第 1 台变回 `healthy`

> ⚠️ 不等就部署第 2 台，可能两台同时不可用 → 503

**Step 9**　第 2 台重复 Step 6〜8

**Step 10**　浏览器验证

**不是确认「能打开」，是确认「这次改的地方变了」。** 部署前就列好：

```
| 确认项 | 期待结果 | 结果 |
```

> ALB 会轮询分配，**刷新 5〜6 次**。每次显示不一样 = 两台的 war 不一致。

**Step 11**　通知团队（日文）

```
皆様

AWSに最新版をデプロイしました。

■ 変更内容
 ・
 ・

■ ご注意
 Tomcatを再起動しているため、再度ログインをお願いします。

よろしくお願いいたします。
```

### 回滚

用 Step 6 备份的 war 重复 Step 6。

### 失败模式
| 症状 | 原因 | 对处 |
|---|---|---|
| scp 报 usage 错误 | 只写了目标，漏了源文件 | 补上源文件 |
| `Could not resolve hostname <1.2.3.4>` | 占位符的尖括号没删 | 删掉 `< >` |
| 部署后行为没变 | 没删 `webapps/ROOT` 目录 | 加 `rm -rf` 重做 + Ctrl+F5 |
| 日志 `Permission denied` | 没 `chown` | 执行 chown 后重启 |
| 画面 503 | 2 台同时在重启 | 等时间常数 |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | IP 被重新分配给了别的机器 | `ssh-keygen -R <IP>` |
| `UNPROTECTED PRIVATE KEY FILE` | pem 权限太松 | 属性 → 安全 → 高级 → 禁用继承 → 删除自己以外 |

---

## P-21　公开 URL / 路径的变更

### 变更点一览（**四处都要改，漏一处就 404**）

| # | 对象 | 内容 |
|---|---|---|
| 1 | war 的部署名 | `app.war` → `ROOT.war`（根路径发布时） |
| 2 | httpd 的反向代理设定 | ProxyPass 的路径 |
| 3 | 目标组的健康检查路径 | 新路径 |
| 4 | IaC 的 UserData / Outputs | 无法更新时记入 `DIFF_LOG.md` |

### 执行步骤

**Step 1**　备份 httpd 设定

> 场所：EC2

```
sudo cp /etc/httpd/conf.d/<设定文件>.conf /etc/httpd/conf.d/<设定文件>.conf.bak.$(date +%Y%m%d)
```

**Step 2**　编辑设定。**排除规则要在一般规则前面**

```apache
# 管理用アプリはインターネットに公開しない
ProxyPass /manager !
ProxyPass /host-manager !
ProxyPass /docs !
ProxyPass /examples !

ProxyPass / ajp://localhost:8009/
ProxyPassReverse / ajp://localhost:8009/
```

> ⚠️ `ProxyPass /manager !` 必须在 `ProxyPass /` **之前**，顺序反了排除不生效

**Step 3**　语法检查

```
sudo httpd -t
```

期待：`Syntax OK`

**Step 4**　重载

```
sudo systemctl reload httpd
```

**Step 5**　清理 `webapps` 下的多余目录

```
sudo ls -l <CATALINA>/webapps
```

> ⚠️ **Tomcat 会把 `webapps/` 下的任何目录当应用发布。**
> 备份目录会以 `/<目录名>` 被公开。移到 webapps 外面：

```
sudo mv <CATALINA>/webapps/<多余目录> /home/ec2-user/
```

**Step 6**　本机验证

```
curl -s -o /dev/null -w "%{http_code}\n" http://localhost<新路径>
```

**Step 7**　另一台重复 Step 1〜6

**Step 8**　按 P-12 改健康检查路径

**Step 9**　从互联网访问新 URL 验证

**Step 10**　记入 `DIFF_LOG.md`

> ⚠️ **UserData 里的设定，环境重建时会跑一遍恢复成旧值 → URL 404。**
> 这一条必须写进差分一览的「重建时的再适用手顺」。

### 回滚

```
sudo cp /etc/httpd/conf.d/<设定文件>.conf.bak.YYYYMMDD /etc/httpd/conf.d/<设定文件>.conf
sudo httpd -t && sudo systemctl reload httpd
```

---

## P-30　异常系测试：DB 接续不可的再现

### 手段的选择

| 手段 | 表现 | 复旧 | 推荐 |
|---|---|---|---|
| 删 RDS SG 的 3306 | 连接挂起 → **504**（不是应用错误画面） | 即时 | △ |
| 停止 RDS | 同上 + **启动要 20 分** | 20 分 | ✗ |
| **临时改 DB 用户密码** | **立刻 Access denied → 应用的错误画面** | 即时 | **◎** |

> **想验证「应用正确处理了 DB 错误」时，必须选能立刻返回错误的手段。**

### 执行步骤

**Step 1**　通知（日文）

```
■ HH:MM〜HH:MM　DB接続不可テストを実施します
　→ 実施中は全機能がDBエラーになります。ログインもできません。
　　 対象の方は HH:MM までにログインし、
　　 DB接続が発生する操作の直前まで入力して待機してください。
　　 それ以外の方は HH:MM 前に作業を区切ってください。
完了後にあらためて連絡します。
```

**Step 2**　各担当**事先确认正常动作**，停在操作前一步

> 这一步是为了切分「这个错误是设置导致的」

**Step 3**　改密码

> 场所：EC2

```
mysql -h <RDS_EP> -u <DB_USER> -p
```

```sql
ALTER USER '<应用用的DB用户>'@'%' IDENTIFIED BY 'TempBroken_<日期>';
```
```sql
FLUSH PRIVILEGES;
```

**Step 4**　通知「変更完了」

**Step 5**　各担当确认

- ① 显示错误画面
- ② **画面上没有内部信息泄露**
  右键 → **ページのソースを表示**（Ctrl+U）→ Ctrl+F 搜索，**都不应存在**：
  ```
  Exception
  SQLException
  Caused by
  at <包名>
  ```
- ③ 截图留证

**Step 6**　**【必须】复旧**

```sql
ALTER USER '<应用用的DB用户>'@'%' IDENTIFIED BY '<原密码>';
```
```sql
FLUSH PRIVILEGES;
```

**Step 7**　**【必须】复旧确认** —— 自己从画面实际操作一次

**Step 8**　通知「復旧完了」

### 失败模式
| 症状 | 原因 | 对处 |
|---|---|---|
| 出 504 而不是错误画面 | 用了安全组手段 | 换密码手段 |
| 密码改回去了还是连不上 | 应用有连接池缓存了坏连接 | 重启 Tomcat |
| 忘了原密码 | — | 应用的配置文件里有（如 `db.properties`） |

---

## P-31　异常系测试：会话超时的再现

### 手段的选择

| 手段 | 影响范围 | 推荐 |
|---|---|---|
| **删浏览器的会话 Cookie** | **只有自己的浏览器** | **◎** |
| 重启 Tomcat（1 台） | 那台的全部会话 + 150 秒回复 | △ |
| 重启 Tomcat（全台） | 全员全部会话 | 需要全员失效时 |
| 等待超时（默认 30 分） | 只有自己 | 太慢 |

### 手段 A：删 Cookie（推荐）

**Step 1**　登录，走到要测的前一步。**不要按目标按钮**

**Step 2**　**F12** 打开开发者工具

**Step 3**　选 **Application（アプリケーション）** 标签

> 找不到 → 被折叠了。点工具栏的 **`>>`** 选它，或把面板拉宽

**Step 4**　左侧树：**Storage** → **Cookie** → 选目标域名

**Step 5**　找会话 Cookie（Tomcat 是 `JSESSIONID`），**右键 → 删除**

> Console 里敲 `document.cookie` 删不掉 —— 会话 Cookie 带 `HttpOnly`

**Step 6**　**不要按 F5**，直接点目标按钮

**Step 7**　确认跳错误画面，截图

**Step 8**　重新登录即可，无需其他复旧

**不用开发者工具的替代**：地址栏左边的**锁图标** → **Cookie とサイトデータ** → **保存されているサイトデータを管理** → 删除

### 手段 B：重启 Tomcat（需要全员失效时）

**Step 1**　通知。**必须写明「等我说完了再操作」**（日文）

```
■ HH:MM　Tomcatを再起動します
　→ 全員のログインセッションが切れます。

　 セッションエラーを確認する方：
　 　HH:MM までに対象画面を開き、ボタンは押さずに待機してください。
　 　「再起動完了」と連絡したら、F5を押さずにボタンを押してください。

　 それ以外の方：
　 　入力中の内容が失われます。HH:MM 前に一旦区切ってください。
　 　復旧後は再ログインが必要です。
```

**Step 2**　开 N 个窗口，每个 SSH 进一台

**Step 3**　每个窗口把命令敲好**不要回车**

```
sudo systemctl restart tomcat
```

> **必须 N 台同时重启。** 只重启 1 台，被 ALB 分到另一台的人会话还在，测不出来

**Step 4**　到点，所有窗口同时回车

**Step 5**　确认启动完成。`systemctl restart` 返回 ≠ 应用可用

```
sudo tail -5 <CATALINA>/logs/catalina.out
```

或：

```
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080<健康检查路径>
```

期待：`200`

**Step 6**　全台确认后通知「再起動完了」

**Step 7**　各担当操作确认

**Step 8**　**等满时间常数**，确认全部 `healthy`，通知「復旧完了」

---

## P-40　数据的生命周期管理

### 三个阶段

| 阶段 | 状态 | 谁决定 |
|---|---|---|
| 测试期间 | 测试数据持续增加 | — |
| 验收演示前 | **能完成演示的最小数据集** | 自己 + 功能负责人 |
| 交付时 | **只留主数据，业务/历史数据 0 件** | **必须向上位确认** |

### 执行步骤

**Step 1**　**取备份（P-10）**。没有备份不许往下

**Step 2**　把表分成两类，**列举表名**。不要用「除了 xx 以外」

```
## 删除对象（业务/历史系）
## 不动（主数据系）
```

**Step 3**　记录删除前件数（证据）

```sql
SELECT '<表1>' tbl, COUNT(*) cnt FROM <表1> UNION ALL SELECT '<表2>', COUNT(*) FROM <表2>;
```

**截图**

**Step 4**　**确认发号逻辑**

```sql
-- 危险：COUNT 基
SELECT COUNT(*) + 1 FROM <表>;
-- 安全：MAX 基
SELECT IFNULL(MAX(<列>), 0) + 1 FROM <表>;
```

| 情况 | 对策 |
|---|---|
| MAX 基 | 部分删除 OK |
| **COUNT 基** | **只能全删，从 0 件重新发号** |

**Step 5**　执行删除。**外键的子表在前**

全部删除：

```sql
USE <DB_NAME>;
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE <子表>;
TRUNCATE TABLE <中间表>;
TRUNCATE TABLE <父表>;
SET FOREIGN_KEY_CHECKS = 1;
```

> ⚠️ `SET FOREIGN_KEY_CHECKS = 1;` **必须执行**
> `TRUNCATE` 会重置 AUTO_INCREMENT，`DELETE` 不会

部分删除：

```sql
DELETE FROM <子表>   WHERE <主键> <> '<保留的值>';
DELETE FROM <父表>   WHERE <主键> <> '<保留的值>';
```

**Step 6**　确认删除后件数

**Step 7**　**确认主数据无损伤**

```sql
SELECT (SELECT COUNT(*) FROM <主表1>) t1, (SELECT COUNT(*) FROM <主表2>) t2;
```

与 Step 3 之前的值一致才算过

**Step 8**　从画面实际操作确认功能正常

**Step 9**　通知团队

### 失败模式
| 症状 | 原因 | 对处 |
|---|---|---|
| `Cannot delete or update a parent row` | 删除顺序反了 | 子表先删 |
| 删除后应用报错 | COUNT 基发号撞号 | 全删后重新生成 |
| 主数据件数变了 | 删错表了 | 立刻从备份恢复 |

---

## P-50　成本算出

### 路线 A：Cost Explorer（标签已启用时）

> 场所：CloudShell　⚠️ **区域必须是 `us-east-1`**（Cost Explorer API 只在那里）

```
aws ce get-cost-and-usage --time-period Start=<YYYY-MM-DD>,End=<YYYY-MM-DD> --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE --region us-east-1 --output table
```

标签过滤：

```
aws ce get-cost-and-usage --time-period Start=<YYYY-MM-DD>,End=<YYYY-MM-DD> --granularity MONTHLY --metrics UnblendedCost --filter '{"Tags":{"Key":"<标签键>","Values":["<标签值>"]}}' --group-by Type=DIMENSION,Key=SERVICE --region us-east-1 --output table
```

### 路线 B：手算（共用账号 + 标签未启用）

**Step 1**　分清哪些停了也收钱

| 资源 | 停止中 | 计费时间 |
|---|---|---|
| EC2 / RDS 实例 | 不计费 | 运行时间 |
| **EBS 卷** | **计费** | **24h × 天数** |
| **RDS 存储** | **计费** | **24h × 天数** |
| **ALB** | **计费** | **24h × 天数** + LCU |
| 未附加的 EIP | 计费 | 24h × 天数 |

**Step 2**　算运行时间

```
每天运行时间 = 停止时刻 - 启动时刻
总运行时间 = 每天 × 运行天数 × 台数
```

实际次数从 CloudTrail 数：

```
aws cloudtrail lookup-events --region <REGION> --lookup-attributes AttributeKey=EventName,AttributeValue=StartInstances --max-results 50 --query 'Events[].EventTime' --output table
```

**Step 3**　取单价（AWS Price List API）

EC2：

```
aws pricing get-products --service-code AmazonEC2 --region us-east-1 --filters Type=TERM_MATCH,Field=instanceType,Value=<实例类型> Type=TERM_MATCH,Field=location,Value="<区域全称>" Type=TERM_MATCH,Field=operatingSystem,Value=Linux Type=TERM_MATCH,Field=tenancy,Value=Shared Type=TERM_MATCH,Field=preInstalledSw,Value=NA Type=TERM_MATCH,Field=capacitystatus,Value=Used --output json | python3 -c "import json,sys; d=json.load(sys.stdin); p=json.loads(d['PriceList'][0]); [print(k, v['pricePerUnit']) for t in p['terms']['OnDemand'].values() for k,v in t['priceDimensions'].items()]"
```

RDS：

```
aws pricing get-products --service-code AmazonRDS --region us-east-1 --filters Type=TERM_MATCH,Field=instanceType,Value=<DB实例类型> Type=TERM_MATCH,Field=location,Value="<区域全称>" Type=TERM_MATCH,Field=databaseEngine,Value=<引擎> Type=TERM_MATCH,Field=deploymentOption,Value="<Single-AZ 或 Multi-AZ>" --output json | python3 -c "import json,sys; d=json.load(sys.stdin); p=json.loads(d['PriceList'][0]); [print(k, v['pricePerUnit']) for t in p['terms']['OnDemand'].values() for k,v in t['priceDimensions'].items()]"
```

> 区域名用**全称**，如 `Asia Pacific (Tokyo)`，不是 `ap-northeast-1`

**Step 4**　填计算表

```
| 资源 | 台数 | 单价(USD/h) | 计费时间(h) | 小计(USD) |
```

**Step 5**　换算当地货币，注明汇率和取得日

### 失败模式
| 症状 | 原因 | 对处 |
|---|---|---|
| Cost Explorer API 报错 | 区域不是 us-east-1 | 加 `--region us-east-1` |
| 标签过滤结果为 0 | 标签未启用，或启用日之后才有数据 | 走路线 B |
| 算出来比实际低很多 | 漏了 ALB / 存储 / 数据传输 | 按 Step 1 的表重查 |

---

## P-60　差分记录

IaC 无法更新时，**手动变更必须记录**，否则环境重建时静默回退。

写进 `workspace/DIFF_LOG.md`：

```
| # | 项目 | 模板/初期值 | 现在的值 | 变更日 | 变更理由 | 重建时的再适用手顺 |
```

**漂移检测要在变更之后重新取**（变更前的 `IN_SYNC` 不是证据）：

```
aws cloudformation detect-stack-drift --region <REGION> --stack-name <栈名>
```

```
aws cloudformation describe-stack-resource-drifts --region <REGION> --stack-name <栈名> --stack-resource-drift-status-filters MODIFIED DELETED --query 'StackResourceDrifts[].{Res:LogicalResourceId,Status:StackResourceDriftStatus}' --output table
```

---

## P-70　确认事项书的作成

自己决定不了的事，攒够几条一起提交效率最高。

### 格式（日文）

```
# インフラ 確認・相談事項

作成日：YYYY/MM/DD
調査方法：AWS CLI による構成の読み取り

---

## A. 対応が必要と考えられる事項

### A-1. <标题>

| | |
|---|---|
| 現状 | 事実のみ。設定値をそのまま書く |
| 影響 | 何が起きるか / 起きていないか |
| 懸念 | なぜ問題か |
| 対応案 | 具体的な変更内容 |
| 影響範囲 | 変更した場合に何が変わるか |

---

## B. ご判断をいただきたい事項

### B-1. <标题>

| | |
|---|---|
| 現状 | |
| ご相談 | 何を決めてほしいか1行で |

---

## C. 本作業により発生した差分（記録）

## D. 参考（緊急性は低いと判断した事項）
```

### 常见的确认事项（检查用）

- [ ] SSH（22番）的公开范围
- [ ] **RDS 自动备份是否实际在执行**
- [ ] 调度的实施期间（月指定 / EndDate）
- [ ] 死活监视的通知先是否设置
- [ ] 计划停止会不会误报警
- [ ] SNS 订阅者是否只有 1 人 / 是否已承认
- [ ] HTTP → HTTPS 重定向
- [ ] IaC 原始模板的所在
- [ ] ALB 的监控（`UnHealthyHostCount` / `HTTPCode_ELB_5XX_Count`）
- [ ] AJP 等内部连接器的绑定地址
- [ ] Multi-AZ 等冗余配置是否符合要求
- [ ] 中间件同捆的管理应用是否可删
