#!/bin/bash
# =====================================================================
# AWS 构成审计（CloudShell 上执行）
#
#   用法：
#     bash scripts/audit.sh | tee ~/audit-$(date +%Y%m%d).txt
#     AWS_REGION=ap-northeast-1 bash scripts/audit.sh
#
#   做两件事：
#     第1部　设计书不需要就能机械判定的项目 → PASS / WARN / FAIL
#     第2部　必须对照设计书才能判定的项目 → 输出数据（交给 AI 用 A-11 对照）
#
#   FAIL = 几乎确定是问题
#   WARN = 可能是暂定设定。对照 TEMP_SETTINGS.md 判断
# =====================================================================

R=${AWS_REGION:-ap-northeast-1}
P=0; W=0; FL=0

pass(){ echo "[PASS] $1"; P=$((P+1)); }
warn(){ echo "[WARN] $1"; W=$((W+1)); }
fail(){ echo "[FAIL] $1"; FL=$((FL+1)); }
sec(){ echo; echo "──────────────────────────────────────────"; echo "$1"; echo "──────────────────────────────────────────"; }

command -v jq >/dev/null || { echo "jq が必要です。CloudShell 以外で実行する場合はインストールしてください。"; exit 1; }

echo "=========================================="
echo " AWS 構成監査　$(date)"
echo " REGION = $R"
echo "=========================================="

# =====================================================================
sec "第1部　設計書なしで判定できる項目"
# =====================================================================

# ---------- 1. セキュリティグループ ----------
echo; echo "■ 1. セキュリティグループ"

SGS=$(aws ec2 describe-security-groups --region $R --output json)

# 1-1 SSH 22 が全開放
echo "$SGS" | jq -r '.SecurityGroups[] | . as $sg | .IpPermissions[]?
  | select((.FromPort//0) <= 22 and (.ToPort//65535) >= 22)
  | .IpRanges[]? | select(.CidrIp=="0.0.0.0/0")
  | "\($sg.GroupName)"' | sort -u | while read g; do
  [ -n "$g" ] && echo "__FAIL__ SSH(22) が 0.0.0.0/0 に開放されています： $g"
done > /tmp/_a1 ; while read l; do [ -n "$l" ] && fail "${l#__FAIL__ }"; done < /tmp/_a1
[ ! -s /tmp/_a1 ] && pass "SSH(22) の全開放なし"

# 1-2 ELB 以外のSGで 80/443 が全開放
ELBSG=$(aws elbv2 describe-load-balancers --region $R --query 'LoadBalancers[].SecurityGroups[]' --output text 2>/dev/null | tr '\t' '\n' | sort -u)
echo "$SGS" | jq -r '.SecurityGroups[] | . as $sg | .IpPermissions[]?
  | select(.FromPort==80 or .FromPort==443)
  | .IpRanges[]? | select(.CidrIp=="0.0.0.0/0")
  | "\($sg.GroupId) \($sg.GroupName)"' | sort -u > /tmp/_a2
FOUND=0
while read id name; do
  [ -z "$id" ] && continue
  if echo "$ELBSG" | grep -q "^$id$"; then
    : # ELB 的 SG 开 80/443 是正常的
  else
    fail "ELB以外のSGで HTTP/HTTPS が 0.0.0.0/0 に開放： $name ($id)　※ELBのSGを指定すべき"
    FOUND=1
  fi
done < /tmp/_a2
[ $FOUND -eq 0 ] && pass "ELB以外のSGに HTTP/HTTPS の全開放なし"

# 1-3 DB ポートが全開放
echo "$SGS" | jq -r '.SecurityGroups[] | . as $sg | .IpPermissions[]?
  | select(.FromPort==3306 or .FromPort==5432 or .FromPort==1521 or .FromPort==1433)
  | .IpRanges[]? | select(.CidrIp=="0.0.0.0/0")
  | "\($sg.GroupName) port=\($sg.IpPermissions[0].FromPort//"?")"' | sort -u > /tmp/_a3
if [ -s /tmp/_a3 ]; then
  while read l; do fail "DBポートが 0.0.0.0/0 に開放： $l"; done < /tmp/_a3
else
  pass "DBポートの全開放なし"
fi

# ---------- 2. ロードバランサー / リスナー ----------
echo; echo "■ 2. ロードバランサー・リスナー"

ALBS=$(aws elbv2 describe-load-balancers --region $R --output json)
NALB=$(echo "$ALBS" | jq '.LoadBalancers | length')
if [ "$NALB" -eq 0 ]; then
  warn "ロードバランサーが存在しません"
else
  echo "$ALBS" | jq -r '.LoadBalancers[] | "\(.LoadBalancerArn)\t\(.LoadBalancerName)"' | while IFS=$'\t' read arn name; do
    LS=$(aws elbv2 describe-listeners --region $R --load-balancer-arn "$arn" --output json)
    HAS80=$(echo "$LS" | jq '[.Listeners[] | select(.Protocol=="HTTP" and .Port==80)] | length')
    HAS443=$(echo "$LS" | jq '[.Listeners[] | select(.Protocol=="HTTPS")] | length')
    if [ "$HAS443" -gt 0 ] && [ "$HAS80" -gt 0 ]; then
      echo "__FAIL__ $name : HTTPS構成済みなのに HTTP:80 リスナーが残っています（SSL化後は削除対象）"
    elif [ "$HAS443" -eq 0 ]; then
      echo "__WARN__ $name : HTTPSリスナーがありません（SSL化前なら正常）"
    else
      echo "__PASS__ $name : リスナーは HTTPS のみ"
    fi
    # HTTP リスナーがリダイレクトなら OK
    RED=$(echo "$LS" | jq '[.Listeners[] | select(.Port==80) | .DefaultActions[] | select(.Type=="redirect")] | length')
    [ "$HAS80" -gt 0 ] && [ "$RED" -gt 0 ] && echo "__PASS__ $name : HTTP:80 は HTTPS へのリダイレクト設定"
  done > /tmp/_a4
  while read l; do
    case "$l" in
      __FAIL__*) fail "${l#__FAIL__ }";;
      __WARN__*) warn "${l#__WARN__ }";;
      __PASS__*) pass "${l#__PASS__ }";;
    esac
  done < /tmp/_a4
fi

# ---------- 3. 開閉局 Lambda の参照先 ----------
echo; echo "■ 3. 開閉局処理（リスナー切替型）の参照先"

ALL_LISTENERS=$(aws elbv2 describe-load-balancers --region $R --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null | tr '\t' '\n' | while read a; do
  [ -n "$a" ] && aws elbv2 describe-listeners --region $R --load-balancer-arn "$a" --query 'Listeners[].ListenerArn' --output text
done | tr '\t' '\n' | sort -u)

FOUND_L=0
for f in $(aws lambda list-functions --region $R --query 'Functions[].FunctionName' --output text 2>/dev/null); do
  ENV=$(aws lambda get-function-configuration --region $R --function-name "$f" --query 'Environment.Variables' --output json 2>/dev/null)
  echo "$ENV" | grep -q "listener/" || continue
  FOUND_L=1
  for arn in $(echo "$ENV" | jq -r '.[]?' | tr ',' '\n' | grep "listener/" | tr -d ' "'); do
    if echo "$ALL_LISTENERS" | grep -q "^$arn$"; then
      PROTO=$(aws elbv2 describe-listeners --region $R --listener-arns "$arn" --query 'Listeners[0].Protocol' --output text 2>/dev/null)
      if [ "$PROTO" = "HTTPS" ]; then
        pass "$f : 参照先リスナーは存在し HTTPS （$arn）"
      else
        warn "$f : 参照先リスナーは $PROTO です。HTTPS化済みなら HTTPS のARNに変更が必要"
      fi
    else
      fail "$f : 参照先リスナーが存在しません（削除済み）。開閉局は無言で機能しません → $arn"
    fi
  done
done
[ $FOUND_L -eq 0 ] && echo "  （リスナーARNを参照する Lambda は見つかりませんでした）"

# ---------- 4. RDS ----------
echo; echo "■ 4. RDS"

RDSJ=$(aws rds describe-db-instances --region $R --output json)
NRDS=$(echo "$RDSJ" | jq '.DBInstances | length')
if [ "$NRDS" -eq 0 ]; then
  echo "  （RDSインスタンスなし）"
else
  echo "$RDSJ" | jq -r '.DBInstances[] | "\(.DBInstanceIdentifier)\t\(.PubliclyAccessible)\t\(.StorageEncrypted)\t\(.BackupRetentionPeriod)\t\(.PreferredBackupWindow)\t\(.MultiAZ)"' | while IFS=$'\t' read id pub enc days win maz; do
    [ "$pub" = "true" ] && echo "__FAIL__ $id : PubliclyAccessible = true（インターネットから到達可能）" || echo "__PASS__ $id : PubliclyAccessible = false"
    [ "$enc" = "false" ] && echo "__WARN__ $id : ストレージ暗号化が無効" || echo "__PASS__ $id : ストレージ暗号化 有効"
    [ "$maz" = "false" ] && echo "__WARN__ $id : Multi-AZ 無効（設計要件を確認）"
    if [ "$days" = "0" ]; then
      echo "__FAIL__ $id : 自動バックアップ無効（BackupRetentionPeriod=0）"
    else
      # バックアップが実際に取れているか
      N=$(aws rds describe-db-snapshots --region $R --db-instance-identifier "$id" --snapshot-type automated --query 'length(DBSnapshots)' --output text 2>/dev/null)
      if [ "$N" = "0" ] || [ -z "$N" ]; then
        echo "__FAIL__ $id : 保持期間 ${days}日 の設定があるのに自動スナップショットが0件。バックアップウィンドウ($win UTC)が停止時間帯と重なっている可能性"
      else
        LAST=$(aws rds describe-db-snapshots --region $R --db-instance-identifier "$id" --snapshot-type automated --query 'sort_by(DBSnapshots,&SnapshotCreateTime)[-1].SnapshotCreateTime' --output text 2>/dev/null)
        echo "__PASS__ $id : 自動スナップショット ${N}件（最新 $LAST）"
      fi
    fi
  done > /tmp/_a5
  while read l; do
    case "$l" in
      __FAIL__*) fail "${l#__FAIL__ }";;
      __WARN__*) warn "${l#__WARN__ }";;
      __PASS__*) pass "${l#__PASS__ }";;
    esac
  done < /tmp/_a5
fi

# ---------- 5. 通知 ----------
echo; echo "■ 5. 監視・通知"

for t in $(aws sns list-topics --region $R --query 'Topics[].TopicArn' --output text 2>/dev/null); do
  SUBS=$(aws sns list-subscriptions-by-topic --region $R --topic-arn "$t" --output json 2>/dev/null)
  N=$(echo "$SUBS" | jq '.Subscriptions | length')
  PEND=$(echo "$SUBS" | jq '[.Subscriptions[] | select(.SubscriptionArn=="PendingConfirmation")] | length')
  NAME=${t##*:}
  if [ "$N" = "0" ]; then
    warn "SNS $NAME : 購読者が0件（通知は誰にも届きません）"
  elif [ "$PEND" -gt 0 ]; then
    fail "SNS $NAME : 未承認の購読が ${PEND}件。**アラームがALARMになってもメールは届きません**"
  else
    [ "$N" = "1" ] && warn "SNS $NAME : 購読者が1名のみ（担当者不在時に検知できない）" || pass "SNS $NAME : 購読者 ${N}名、全員承認済み"
  fi
done

ALM=$(aws cloudwatch describe-alarms --region $R --output json)
NALM=$(echo "$ALM" | jq '.MetricAlarms | length')
if [ "$NALM" = "0" ]; then
  warn "CloudWatch アラームが1件もありません"
else
  NOACT=$(echo "$ALM" | jq -r '.MetricAlarms[] | select((.AlarmActions|length)==0) | .AlarmName')
  if [ -n "$NOACT" ]; then
    echo "$NOACT" | while read a; do echo "__FAIL__ アラーム $a : 通知アクションが未設定（発報しても誰も気づきません）"; done > /tmp/_a6
    while read l; do fail "${l#__FAIL__ }"; done < /tmp/_a6
  else
    pass "全アラームに通知アクションが設定されています（${NALM}件）"
  fi
fi

# ---------- 6. スケジュール ----------
echo; echo "■ 6. スケジュール"

TODAY=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FOUND_S=0
for s in $(aws scheduler list-schedules --region $R --query 'Schedules[].Name' --output text 2>/dev/null); do
  FOUND_S=1
  J=$(aws scheduler get-schedule --region $R --name "$s" --output json)
  ST=$(echo "$J" | jq -r '.State'); EXP=$(echo "$J" | jq -r '.ScheduleExpression'); END=$(echo "$J" | jq -r '.EndDate // empty')
  [ "$ST" != "ENABLED" ] && warn "スケジュール $s : State=$ST（発火しません）"
  if [ -n "$END" ]; then
    E=$(date -u -d "$END" +%s 2>/dev/null || echo 0)
    N=$(date -u +%s)
    [ "$E" != "0" ] && [ "$E" -lt "$N" ] && fail "スケジュール $s : EndDate($END) を過ぎています。**もう発火しません**"
  fi
  # cron の月指定
  echo "$EXP" | grep -qE 'cron\([^)]*\)' && {
    MON=$(echo "$EXP" | sed -E 's/.*cron\(([^)]*)\).*/\1/' | awk '{print $4}')
    [ "$MON" != "*" ] && [ -n "$MON" ] && warn "スケジュール $s : cron の月指定が「$MON」。翌月以降は発火しません → $EXP"
  }
done
for r in $(aws events list-rules --region $R --query 'Rules[?ScheduleExpression!=null].Name' --output text 2>/dev/null); do
  FOUND_S=1
  ST=$(aws events describe-rule --region $R --name "$r" --query 'State' --output text)
  [ "$ST" != "ENABLED" ] && warn "EventBridge ルール $r : State=$ST（発火しません）"
done
[ $FOUND_S -eq 0 ] && echo "  （スケジュールなし）"

# ---------- 7. コスト ----------
echo; echo "■ 7. 無駄な課金"

EIP=$(aws ec2 describe-addresses --region $R --query 'Addresses[?AssociationId==null].PublicIp' --output text 2>/dev/null)
[ -n "$EIP" ] && warn "未アタッチの Elastic IP（課金対象）： $EIP" || pass "未アタッチの Elastic IP なし"

VOL=$(aws ec2 describe-volumes --region $R --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text 2>/dev/null)
[ -n "$VOL" ] && warn "未アタッチの EBS ボリューム（課金対象）： $VOL" || pass "未アタッチの EBS なし"

NAT=$(aws ec2 describe-nat-gateways --region $R --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
[ -n "$NAT" ] && warn "NATゲートウェイが稼働中（時間課金）： $NAT"

# ---------- 8. 証明書 ----------
echo; echo "■ 8. 証明書"

FOUND_C=0
for c in $(aws acm list-certificates --region $R --query 'CertificateSummaryList[].CertificateArn' --output text 2>/dev/null); do
  FOUND_C=1
  J=$(aws acm describe-certificate --region $R --certificate-arn "$c" --output json)
  D=$(echo "$J" | jq -r '.Certificate.DomainName'); ST=$(echo "$J" | jq -r '.Certificate.Status')
  NA=$(echo "$J" | jq -r '.Certificate.NotAfter // empty'); USE=$(echo "$J" | jq '.Certificate.InUseBy | length')
  [ "$ST" != "ISSUED" ] && fail "証明書 $D : Status=$ST"
  [ "$USE" = "0" ] && warn "証明書 $D : どのリソースにも紐づいていません（InUseBy が空）"
  if [ -n "$NA" ]; then
    E=$(date -u -d "$NA" +%s 2>/dev/null || echo 0); N=$(date -u +%s)
    if [ "$E" != "0" ]; then
      DAYS=$(( (E - N) / 86400 ))
      [ "$DAYS" -lt 30 ] && fail "証明書 $D : 有効期限まで残り ${DAYS}日" || pass "証明書 $D : 有効期限まで ${DAYS}日"
    fi
  fi
done
[ $FOUND_C -eq 0 ] && warn "ACM 証明書が1件もありません（SSL化前なら正常）"

# ---------- 9. ターゲットの健全性 ----------
echo; echo "■ 9. ターゲットの健全性"

for t in $(aws elbv2 describe-target-groups --region $R --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null); do
  NM=$(aws elbv2 describe-target-groups --region $R --target-group-arns "$t" --query 'TargetGroups[0].TargetGroupName' --output text)
  UN=$(aws elbv2 describe-target-health --region $R --target-group-arn "$t" --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output text 2>/dev/null)
  if [ -n "$UN" ]; then
    warn "ターゲットグループ $NM : healthy でないターゲットあり → $UN"
  else
    pass "ターゲットグループ $NM : 全ターゲット healthy"
  fi
done

# ---------- 10. CloudFormation ドリフト ----------
echo; echo "■ 10. CloudFormation"

for s in $(aws cloudformation describe-stacks --region $R --query 'Stacks[].StackName' --output text 2>/dev/null); do
  D=$(aws cloudformation describe-stacks --region $R --stack-name "$s" --query 'Stacks[0].DriftInformation.StackDriftStatus' --output text 2>/dev/null)
  T=$(aws cloudformation describe-stacks --region $R --stack-name "$s" --query 'Stacks[0].DriftInformation.LastCheckTimestamp' --output text 2>/dev/null)
  case "$D" in
    DRIFTED) warn "スタック $s : DRIFTED（テンプレートと実環境が不一致。差分一覧に記録されているか確認）最終検出 $T";;
    IN_SYNC) pass "スタック $s : IN_SYNC（最終検出 $T）※変更後に取り直したものか確認すること";;
    *)       warn "スタック $s : ドリフト未検出（$D）。detect-stack-drift を実行してください";;
  esac
done

# =====================================================================
sec "第2部　設計書と突き合わせて判定する項目（AI に A-11 で渡す）"
# =====================================================================

echo; echo "■ A. リスナー構成"
for a in $(aws elbv2 describe-load-balancers --region $R --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null); do
  aws elbv2 describe-listeners --region $R --load-balancer-arn "$a" \
    --query 'Listeners[].{Port:Port,Proto:Protocol,DefaultType:DefaultActions[0].Type,Cert:Certificates[0].CertificateArn}' --output table
done

echo; echo "■ B. セキュリティグループ インバウンド全件"
aws ec2 describe-security-groups --region $R --query 'SecurityGroups[].{Name:GroupName,Id:GroupId,Ingress:IpPermissions}' --output json

echo; echo "■ C. ターゲットグループ・ヘルスチェック"
aws elbv2 describe-target-groups --region $R \
  --query 'TargetGroups[].{Name:TargetGroupName,Port:Port,Proto:Protocol,HCProto:HealthCheckProtocol,HCPath:HealthCheckPath,Interval:HealthCheckIntervalSeconds,Healthy:HealthyThresholdCount,Unhealthy:UnhealthyThresholdCount}' --output table

echo; echo "■ D. EC2"
aws ec2 describe-instances --region $R \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,Type:InstanceType,State:State.Name,AZ:Placement.AvailabilityZone,Subnet:SubnetId,SG:SecurityGroups[].GroupName}' --output json

echo; echo "■ E. RDS"
aws rds describe-db-instances --region $R \
  --query 'DBInstances[].{Id:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,Ver:EngineVersion,MultiAZ:MultiAZ,Storage:AllocatedStorage,Encrypted:StorageEncrypted,BackupDays:BackupRetentionPeriod,BackupWin:PreferredBackupWindow,MaintWin:PreferredMaintenanceWindow}' --output table

echo; echo "■ F. スケジュール（cronはUTC。現地時間に換算して突き合わせること）"
aws scheduler list-schedules --region $R --query 'Schedules[].Name' --output text 2>/dev/null | tr '\t' '\n' | while read s; do
  [ -n "$s" ] && aws scheduler get-schedule --region $R --name "$s" --query '{Name:Name,Sched:ScheduleExpression,TZ:ScheduleExpressionTimezone,Start:StartDate,End:EndDate,State:State}' --output json
done
aws events list-rules --region $R --query 'Rules[].{Name:Name,Sched:ScheduleExpression,Pattern:EventPattern,State:State}' --output json

echo; echo "■ G. アラーム"
aws cloudwatch describe-alarms --region $R \
  --query 'MetricAlarms[].{Name:AlarmName,NS:Namespace,Metric:MetricName,Stat:Statistic,Period:Period,Eval:EvaluationPeriods,Threshold:Threshold,Op:ComparisonOperator,Missing:TreatMissingData}' --output table

echo; echo "■ H. Lambda 環境変数"
for f in $(aws lambda list-functions --region $R --query 'Functions[].FunctionName' --output text 2>/dev/null); do
  echo "--- $f ---"
  aws lambda get-function-configuration --region $R --function-name "$f" --query 'Environment.Variables' --output json
done

# =====================================================================
sec "集計"
# =====================================================================
echo "PASS : $P"
echo "WARN : $W"
echo "FAIL : $FL"
echo
if [ $FL -gt 0 ]; then
  echo "▲ FAIL があります。ほぼ確実に是正が必要です。"
elif [ $W -gt 0 ]; then
  echo "△ WARN のみ。暫定設定台帳（TEMP_SETTINGS.md）と突き合わせて、"
  echo "  台帳に無いものは「誰も撤去責任を持っていない設定」として扱ってください。"
else
  echo "○ 機械判定できる範囲では問題なし。第2部を設計書と突き合わせてください。"
fi
echo
echo "=========== END ==========="
