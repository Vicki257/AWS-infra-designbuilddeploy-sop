#!/bin/bash
# AWS 构成一览取得
# 用法（CloudShell 或已配置 CLI 的环境）：
#   bash scripts/inventory.sh > ~/inventory-$(date +%Y%m%d).txt 2>&1
# 区域用环境变量指定（省略时用 AWS_REGION，再省略用东京）：
#   AWS_REGION=ap-northeast-1 bash scripts/inventory.sh
# 只看特定前缀的资源时：
#   PREFIX=myteam bash scripts/inventory.sh

R=${AWS_REGION:-ap-northeast-1}
P=${PREFIX:-}

echo "=========== AWS 構成一覧  $(date) ==========="
echo "REGION=$R  PREFIX=${P:-(全件)}"

echo; echo "### アカウント ###"
aws sts get-caller-identity --output table

echo; echo "### EC2 インスタンス ###"
aws ec2 describe-instances --region $R \
 --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,Type:InstanceType,State:State.Name,AZ:Placement.AvailabilityZone,PrivIP:PrivateIpAddress,PubIP:PublicIpAddress,Id:InstanceId,Profile:IamInstanceProfile.Arn}' \
 --output table

echo; echo "### EBS ボリューム ###"
aws ec2 describe-volumes --region $R \
 --query 'Volumes[].{Name:Tags[?Key==`Name`]|[0].Value,Size:Size,Type:VolumeType,State:State,Id:VolumeId}' --output table

echo; echo "### Elastic IP ###"
aws ec2 describe-addresses --region $R --output table

echo; echo "### VPC / サブネット ###"
aws ec2 describe-vpcs --region $R \
 --query 'Vpcs[].{Name:Tags[?Key==`Name`]|[0].Value,Id:VpcId,Cidr:CidrBlock}' --output table
aws ec2 describe-subnets --region $R \
 --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,Id:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,MapPublicIp:MapPublicIpOnLaunch}' --output table

echo; echo "### セキュリティグループ（インバウンド全件） ###"
aws ec2 describe-security-groups --region $R \
 --query 'SecurityGroups[].{Name:GroupName,Id:GroupId,Desc:Description}' --output table
echo "--- インバウンドルール詳細 ---"
aws ec2 describe-security-groups --region $R \
 --query 'SecurityGroups[].{Name:GroupName,Ingress:IpPermissions}' --output json

echo; echo "### RDS ###"
aws rds describe-db-instances --region $R \
 --query 'DBInstances[].{Id:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,Ver:EngineVersion,MultiAZ:MultiAZ,Storage:AllocatedStorage,StorageType:StorageType,Encrypted:StorageEncrypted,Status:DBInstanceStatus,BackupDays:BackupRetentionPeriod,BackupWin:PreferredBackupWindow,MaintWin:PreferredMaintenanceWindow,Public:PubliclyAccessible,EP:Endpoint.Address}' \
 --output table

echo; echo "### RDS 自動スナップショット（バックアップが実際に取れているかの証拠） ###"
for db in $(aws rds describe-db-instances --region $R --query 'DBInstances[].DBInstanceIdentifier' --output text); do
  echo "--- $db ---"
  aws rds describe-db-snapshots --region $R --db-instance-identifier $db --snapshot-type automated \
   --query 'DBSnapshots[].{Id:DBSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' --output table
done

echo; echo "### ロードバランサー ###"
aws elbv2 describe-load-balancers --region $R \
 --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,Scheme:Scheme,DNS:DNSName,State:State.Code,SG:SecurityGroups,Arn:LoadBalancerArn}' --output json

echo; echo "### リスナー ###"
for a in $(aws elbv2 describe-load-balancers --region $R --query 'LoadBalancers[].LoadBalancerArn' --output text); do
  echo "--- $a ---"
  aws elbv2 describe-listeners --region $R --load-balancer-arn $a \
   --query 'Listeners[].{Port:Port,Proto:Protocol,DefaultType:DefaultActions[0].Type,Cert:Certificates[0].CertificateArn,Arn:ListenerArn}' --output table
done

echo; echo "### ターゲットグループ ###"
aws elbv2 describe-target-groups --region $R \
 --query 'TargetGroups[].{Name:TargetGroupName,Port:Port,Proto:Protocol,HCProto:HealthCheckProtocol,HCPath:HealthCheckPath,Interval:HealthCheckIntervalSeconds,Healthy:HealthyThresholdCount,Unhealthy:UnhealthyThresholdCount,Arn:TargetGroupArn}' --output table

echo; echo "### ターゲットの健全性 ###"
for t in $(aws elbv2 describe-target-groups --region $R --query 'TargetGroups[].TargetGroupArn' --output text); do
  aws elbv2 describe-target-health --region $R --target-group-arn $t \
   --query 'TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' --output table
done

echo; echo "### ACM 証明書 ###"
aws acm list-certificates --region $R --output table
for c in $(aws acm list-certificates --region $R --query 'CertificateSummaryList[].CertificateArn' --output text); do
  aws acm describe-certificate --region $R --certificate-arn $c \
   --query 'Certificate.{Domain:DomainName,Status:Status,NotAfter:NotAfter,InUse:InUseBy}' --output json
done

echo; echo "### Route53 ホストゾーン ###"
aws route53 list-hosted-zones --query 'HostedZones[].{Name:Name,Id:Id}' --output table 2>/dev/null

echo; echo "### Lambda ###"
aws lambda list-functions --region $R \
 --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Mem:MemorySize,Timeout:Timeout}' --output table
echo "--- 環境変数（開閉局の対象ARN確認用） ---"
for f in $(aws lambda list-functions --region $R --query 'Functions[].FunctionName' --output text); do
  echo "--- $f ---"
  aws lambda get-function-configuration --region $R --function-name $f \
   --query 'Environment.Variables' --output json
done

echo; echo "### EventBridge ルール ###"
aws events list-rules --region $R \
 --query 'Rules[].{Name:Name,Sched:ScheduleExpression,Pattern:EventPattern,State:State}' --output json

echo; echo "### EventBridge Scheduler ###"
aws scheduler list-schedules --region $R --output table 2>/dev/null
for s in $(aws scheduler list-schedules --region $R --query 'Schedules[].Name' --output text 2>/dev/null); do
  aws scheduler get-schedule --region $R --name $s \
   --query '{Name:Name,Sched:ScheduleExpression,TZ:ScheduleExpressionTimezone,Start:StartDate,End:EndDate,State:State}' --output json
done

echo; echo "### CloudWatch アラーム ###"
aws cloudwatch describe-alarms --region $R \
 --query 'MetricAlarms[].{Name:AlarmName,Metric:MetricName,Threshold:Threshold,Missing:TreatMissingData,State:StateValue,Actions:AlarmActions[0]}' --output table

echo; echo "### SNS トピックと購読状態（未承認だと通知は届かない） ###"
for t in $(aws sns list-topics --region $R --query 'Topics[].TopicArn' --output text); do
  echo "--- $t ---"
  aws sns list-subscriptions-by-topic --region $R --topic-arn $t \
   --query 'Subscriptions[].{Proto:Protocol,Endpoint:Endpoint,Arn:SubscriptionArn}' --output table
done

echo; echo "### CloudWatch Logs ###"
aws logs describe-log-groups --region $R \
 --query 'logGroups[].{Name:logGroupName,Bytes:storedBytes,Retention:retentionInDays}' --output table

echo; echo "### CloudFormation スタック ###"
aws cloudformation describe-stacks --region $R \
 --query 'Stacks[].{Name:StackName,Status:StackStatus,Created:CreationTime,Drift:DriftInformation.StackDriftStatus}' --output table

echo; echo "### S3 バケット ###"
aws s3 ls

echo; echo "=========== END ==========="
