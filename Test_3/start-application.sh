#!/bin/bash

P=$1
PROFILE=${P:="default"}
REGION=$(aws configure get region --profile $PROFILE)

# ------------ setup first ec2 ------------
INSTANCE_IP_1=$(aws ec2 describe-instances \
                --filter "Name=tag:Name,Values=shorten-url-1" \
                --query 'Reservations[*].Instances[*].{PublicIpAddress:PublicIpAddress}' \
                --profile $PROFILE | jq -r '.[] | .[] | .PublicIpAddress')

echo "Copy application source to instance..."
scp -i ~/.ssh/url_shorten_service_key.pem -r app/ ec2-user@$INSTANCE_IP_1:/home/ec2-user

echo "Startup application..."
../Test_2/awssh.sh shorten-url-1 ~/.ssh/url_shorten_service_key.pem $PROFILE \
    "sudo docker-compose --file /home/ec2-user/app/docker-compose.yaml build app"
../Test_2/awssh.sh shorten-url-1 ~/.ssh/url_shorten_service_key.pem $PROFILE \
    "sudo docker-compose --file /home/ec2-user/app/docker-compose.yaml up -d"

# ------------ setup second ec2 ------------
INSTANCE_IP_2=$(aws ec2 describe-instances \
                --filter "Name=tag:Name,Values=shorten-url-2" \
                --query 'Reservations[*].Instances[*].{PublicIpAddress:PublicIpAddress}' \
                --profile $PROFILE | jq -r '.[] | .[] | .PublicIpAddress')

echo "Copy application source to instance..."
scp -i ~/.ssh/url_shorten_service_key.pem -r app/ ec2-user@$INSTANCE_IP_2:/home/ec2-user

echo "Startup application..."
../Test_2/awssh.sh shorten-url-2 ~/.ssh/url_shorten_service_key.pem $PROFILE \
    "sudo docker-compose --file /home/ec2-user/app/docker-compose.yaml build app"
../Test_2/awssh.sh shorten-url-2 ~/.ssh/url_shorten_service_key.pem $PROFILE \
    "sudo docker-compose --file /home/ec2-user/app/docker-compose.yaml up -d"
