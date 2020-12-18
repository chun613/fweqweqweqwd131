#!/bin/bash

P=$1
PROFILE=${P:="default"}
REGION=$(aws configure get region --profile $PROFILE)

# ------------ DynamoDB ------------
echo "Setup dynamoDB..."
COUNTER_DB="counter"
echo "Check is dynamodb table $COUNTER_DB exist..."
RESP=$(aws dynamodb describe-table \
    --table-name $COUNTER_DB \
    --profile $PROFILE)
if [ $? == "255" ]; then
    echo "Create dynamoDB table: $COUNTER_DB..."
    aws dynamodb create-table \
        --table-name $COUNTER_DB \
        --key-schema AttributeName=ID,KeyType=HASH \
        --attribute-definitions AttributeName=ID,AttributeType=S \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --profile $PROFILE    

    echo "Waiting for table to create..."
    aws dynamodb wait table-exists \
        --table-name $COUNTER_DB \
        --profile $PROFILE

    echo "Insert initial value..."
    aws dynamodb put-item \
        --table-name $COUNTER_DB \
        --item '{"ID":{"S":"1"},"C":{"N":"1"}}' \
        --profile $PROFILE
else 
    echo "$COUNTER_DB table already exist"
fi

SHORTEN_URL_DB="shorten_url"
echo "Check is dynamodb table $SHORTEN_URL_DB exist..."
RESP=$(aws dynamodb describe-table \
    --table-name $SHORTEN_URL_DB \
    --profile $PROFILE)
if [ $? == "255" ]; then
    echo "Create dynamoDB table: $SHORTEN_URL_DB"
    aws dynamodb create-table \
        --table-name $SHORTEN_URL_DB \
        --key-schema AttributeName=id,KeyType=HASH \
        --attribute-definitions AttributeName=id,AttributeType=S AttributeName=long_url,AttributeType=S \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --global-secondary-indexes \
        "[
            {
                \"IndexName\": \"long_url_index\",
                \"KeySchema\": [
                    {\"AttributeName\":\"long_url\",\"KeyType\":\"HASH\"}
                ],
                \"Projection\": {
                    \"ProjectionType\":\"KEYS_ONLY\"
                },
                \"ProvisionedThroughput\": {
                    \"ReadCapacityUnits\": 5,
                    \"WriteCapacityUnits\": 5
                }
            }
        ]" \
        --profile $PROFILE

    echo "Waiting for table to create..."
    aws dynamodb wait table-exists \
        --table-name $SHORTEN_URL_DB \
        --profile $PROFILE
else 
    echo "$SHORTEN_URL_DB table already exist"
fi

# ------------ EC2 related ------------
# vpc
echo "Check is VPC already created..."
VPC_ID=$(aws ec2 describe-vpcs \
    --filters Name=cidr,Values=10.199.0.0/16 \
    --profile $PROFILE | jq -r '.Vpcs[] | select(.State == "available") | .VpcId')
if [ -z $VPC_ID ]; then
    echo "Create VPC 10.199.0.0/16 ..."
    VPC_ID=$(aws ec2 create-vpc \
                --cidr-block 10.199.0.0/16 \
                --profile $PROFILE | jq -r '.Vpc.VpcId')

    # internet gateway
    echo "Create and attach internet gateway..."
    IG_ID=$(aws ec2 create-internet-gateway \
            --profile $PROFILE | jq -r '.InternetGateway.InternetGatewayId')
    aws ec2 attach-internet-gateway \
        --vpc-id $VPC_ID \
        --internet-gateway-id $IG_ID \
        --profile $PROFILE

    # create route to default route table
    echo "Create internet gateway route for route table..."
    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
        --filters Name=vpc-id,Values=$VPC_ID \
        --profile $PROFILE | jq -r '.RouteTables[] | .RouteTableId')
    aws ec2 create-route \
        --route-table-id $ROUTE_TABLE_ID \
        --destination-cidr-block "0.0.0.0/0" \
        --gateway-id $IG_ID \
        --profile $PROFILE
else 
    echo "VPC already exist"
fi
echo "VPC_ID: ${VPC_ID}"

# subnet
echo "Check is Subnet already created..."
SUBNET_ID_1=$(aws ec2 describe-subnets \
            --filters Name=vpc-id,Values=$VPC_ID,Name=cidr-block,Values=10.199.1.0/24 \
            --profile $PROFILE | jq -r '.Subnets[] | select(.State == "available") | .SubnetId')
SUBNET_ID_2=$(aws ec2 describe-subnets \
            --filters Name=vpc-id,Values=$VPC_ID,Name=cidr-block,Values=10.199.2.0/24 \
            --profile $PROFILE | jq -r '.Subnets[] | select(.State == "available") | .SubnetId')
if [ -z $SUBNET_ID_1 ]; then
    echo "Create subnet 10.199.1.0/24..."
    SUBNET_ID_1=$(aws ec2 create-subnet \
                    --cidr-block 10.199.1.0/24 \
                    --vpc-id $VPC_ID \
                    --availability-zone ap-southeast-1a \
                    --profile $PROFILE | jq -r '.Subnet.SubnetId')
    SUBNET_ID_2=$(aws ec2 create-subnet \
                    --cidr-block 10.199.2.0/24 \
                    --vpc-id $VPC_ID \
                    --availability-zone ap-southeast-1b \
                    --profile $PROFILE | jq -r '.Subnet.SubnetId')    
else 
    echo "Subnet already exist"
fi
echo "SUBNET_ID: ${SUBNET_ID_1}, ${SUBNET_ID_2}"

# key pair
echo "Check is key pair created..."
KEY_NAME=$(aws ec2 describe-key-pairs \
            --key-names "url_shorten_service_key" \
            --profile $PROFILE | jq -r '.KeyPairs[] | .KeyName')
if [ -z $KEY_NAME ]; then
    echo "Create key-pair..."
    aws ec2 create-key-pair \
        --key-name url_shorten_service_key \
        --profile $PROFILE | jq -r '.KeyMaterial' > ~/.ssh/url_shorten_service_key.pem 
else 
    echo "Key pair already exist"
fi

# security group
echo "Check is security group created..."
GROUP_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=vpc-08dc794cdc3ae1dde,Name=group-name,Values=url-shorten" \
    --profile $PROFILE | jq -r '.SecurityGroups[] | select(.GroupName == "url-shorten") | .GroupId')
if [ -z $GROUP_ID ]; then
    echo "Create security group..."
    GROUP_ID=$(aws ec2 create-security-group \
            --description "security group for url shorten service" \
            --group-name "url-shorten" \
            --vpc-id $VPC_ID \
            --profile $PROFILE | jq -r '.GroupId')

    echo "Enable ssh access..."
    aws ec2 authorize-security-group-ingress \
        --group-id $GROUP_ID \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --profile $PROFILE

    echo "Enable http access..."
    aws ec2 authorize-security-group-ingress \
        --group-id $GROUP_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --profile $PROFILE
else 
    echo "Security group already exist"
fi
echo "GROUP_ID: ${GROUP_ID}"

# targe group
echo "Check is target group created..."
TG_ARN=$(aws elbv2 describe-target-groups \
    --name "url-shorten-tg" \
    --profile $PROFILE | jq -r '.TargetGroups[] | select(.TargetGroupName == "url-shorten-tg") | .TargetGroupArn')
if [ -z $TG_ARN ]; then
    echo "Create target group..."
    TG_ARN=$(aws elbv2 create-target-group \
        --name url-shorten-tg \
        --protocol HTTP \
        --port 80 \
        --target-type instance \
        --vpc-id $VPC_ID \
        --profile $PROFILE | jq -r '.TargetGroups[] | select(.TargetGroupName == "url-shorten-tg") | .TargetGroupArn')
else 
    echo "Target group already exist"
fi
echo "TARGET_GROUP_ARN: ${TG_ARN}"

# load balancer
echo "Check is load balancer created..."
LB_ARN=$(aws elbv2 describe-load-balancers \
    --names "url-shorten-lb" \
    --profile $PROFILE | jq -r '.LoadBalancers[] | select(.LoadBalancerName == "url-shorten-lb") | .LoadBalancerArn')
if [ -z $LB_ARN ]; then
    echo "Create load balancer..."
    LB_ARN=$(aws elbv2 create-load-balancer \
            --name url-shorten-lb \
            --security-groups $GROUP_ID \
            --subnets $SUBNET_ID_1 $SUBNET_ID_2 \
            --profile $PROFILE | jq -r '.LoadBalancers[] | select(.LoadBalancerName == "url-shorten-lb") | .LoadBalancerArn')
    
    echo "Wait for load balancer to provision..."
    aws elbv2 wait \
        --load-balancer-arns $LB_ARN \
        --profile $PROFILE
else 
    echo "Load balancer already exist"
fi
echo "LB_ARN: ${LB_ARN}"

# load balancer listener
echo "Check is listener created..."
LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn $LB_ARN \
    --profile $PROFILE | jq -r '.Listeners[] | .ListenerArn')
if [ -z $LISTENER_ARN ]; then
    echo "Create load balancer listener..."
    LISTENER_ARN=$(aws elbv2 create-listener \
                    --load-balancer-arn $LB_ARN \
                    --protocol HTTP \
                    --port 80 \
                    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
                    --profile $PROFILE | jq -r '.Listeners[] | .ListenerArn')
else 
    echo "Load balancer listener already exist"
fi
echo "LISTENER_ARN: ${LISTENER_ARN}"

# create role
echo "Check is iam role created..."
ROLE_NAME=$(aws iam get-role \
            --role-name url-shorten-role \
            --profile $PROFILE | jq -r '.Role.RoleName')
if [ -z $ROLE_NAME ]; then
    echo "Create iam role..."
    ROLE_NAME=$(aws iam create-role \
                --role-name url-shorten-role \
                --assume-role-policy-document file://trust-policy.json \
                --profile $PROFILE | jq -r '.Role.RoleName')

    echo "Attach policy to role..."
    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
        --profile $PROFILE
else 
    echo "iam role already exist"
fi
echo "IAM ROLE ARN: ${ROLE_NAME}"

# iam instance profile 
echo "Check is iam instance profile created..."
IAM_PROFILE_NAME=$(aws iam get-instance-profile \
    --instance-profile-name url-shorten-profile \
    --profile $PROFILE | jq -r '.InstanceProfile.InstanceProfileName')
if [ -z $IAM_PROFILE_NAME ]; then
    echo "Create iam instance profile..."
    IAM_PROFILE_NAME=$(aws iam create-instance-profile \
        --instance-profile-name url-shorten-profile \
        --profile $PROFILE | jq -r '.InstanceProfile.InstanceProfileName')
    
    echo "Add role to iam instance profile"
    aws iam add-role-to-instance-profile \
        --instance-profile-name $IAM_PROFILE_NAME \
        --role-name $ROLE_NAME \
        --profile $PROFILE
else
    echo "IAM instance profile already exist"
fi
echo "IAM_PROFILE_NAME: ${IAM_PROFILE_NAME}"

# ------------ ec2 ------------
echo "Check is first ec2 instance created..."
INSTANCE_ID_1=$(aws ec2 describe-instances \
                --filter "Name=tag:Name,Values=shorten-url-1" \
                --query 'Reservations[*].Instances[*].{InstanceId:InstanceId}' \
                --profile $PROFILE | jq -r '.[] | .[] | .InstanceId')
if [ -z $INSTANCE_ID_1 ]; then
    echo "Create ec2 instance..."
    INSTANCE_ID_1=$(aws ec2 run-instances \
                    --image-id ami-0d728fd4e52be968f \
                    --count 1 \
                    --instance-type t2.micro \
                    --key-name url_shorten_service_key \
                    --security-group-ids $GROUP_ID \
                    --subnet-id $SUBNET_ID_1 \
                    --iam-instance-profile Name=$IAM_PROFILE_NAME \
                    --user-data file://bootstrap-ec2.txt \
                    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=shorten-url-1}]' \
                    --associate-public-ip-address \
                    --profile $PROFILE | jq -r '.Instances[] | .InstanceId')
    echo "Wait for ec2 instance to be running..."
    aws ec2 wait instance-running \
        --instance-ids $INSTANCE_ID_1 \
        --profile $PROFILE
else 
    echo "ec2 instance already exist"
fi

echo "Check is second ec2 instance created..."
INSTANCE_ID_2=$(aws ec2 describe-instances \
                --filter "Name=tag:Name,Values=shorten-url-2" \
                --query 'Reservations[*].Instances[*].{InstanceId:InstanceId}' \
                --profile $PROFILE | jq -r '.[] | .[] | .InstanceId')
if [ -z $INSTANCE_ID_2 ]; then
    echo "Create ec2 instance..."
    INSTANCE_ID_2=$(aws ec2 run-instances \
                    --image-id ami-0d728fd4e52be968f \
                    --count 1 \
                    --instance-type t2.micro \
                    --key-name url_shorten_service_key \
                    --security-group-ids $GROUP_ID \
                    --subnet-id $SUBNET_ID_2 \
                    --iam-instance-profile Name=$IAM_PROFILE_NAME \
                    --user-data file://bootstrap-ec2.txt \
                    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=shorten-url-2}]' \
                    --associate-public-ip-address \
                    --profile $PROFILE | jq -r '.Instances[] | .InstanceId')
    echo "Wait for ec2 instance to be running..."
    aws ec2 wait instance-running \
        --instance-ids $INSTANCE_ID_2 \
        --profile $PROFILE
else 
    echo "ec2 instance already exist"
fi

echo "Regsiter first ec2 to target group..."
aws elbv2 register-targets \
    --target-group-arn $TG_ARN \
    --targets Id=$INSTANCE_ID_1,Port=80 \
    --profile $PROFILE

echo "Regsiter second ec2 to target group..."
aws elbv2 register-targets \
    --target-group-arn $TG_ARN \
    --targets Id=$INSTANCE_ID_2,Port=80 \
    --profile $PROFILE

LB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $LB_ARN \
    --profile $PROFILE | jq -r '.LoadBalancers[] | .DNSName')
echo "LB_DNS=${LB_DNS}" > app/env.txt

echo ""
echo ""
echo "example: "
echo "$ curl -i -XPOST http://${LB_DNS}/newurl -H 'Content-Type: application/json' -d '{\"url\":\"https://google.com\"}'"
