#!/bin/bash

print_usage() {
    echo ""
    echo "Usage:"
    echo "./awssh.sh [host name] [key location] [aws profile] [command]"
    echo "[host name]       - host name of the ec2 instance, mandatory"
    echo "[key location]    - ssh key location, mandatory"
    echo "[aws profile]     - the aws profile to be used to query ec2 IP address, default to \"default\", optional"
    echo "[command]         - command to be executed remotely, optional"
    echo ""
}

check_parameter() {
    MESSAGE=$1
    PARAM=$2 
    if [ -z $PARAM ]; then
        echo $MESSAGE
        print_usage
        exit 1
    fi
}

# Verify input parameters
HOST=$1
KEY=$2
AWS_PROFILE=${3:-"default"}
COMMAND=$4
check_parameter "Host can not be empty." $HOST
check_parameter "Key location can not be empty." $KEY

# Find ec2 public ip by aws cli
aws ec2 describe-instances --filters Name=tag:Name,Values=${HOST} --profile $AWS_PROFILE > tmp.txt
if [ ! $? -eq 0 ]; then
    echo "Unable to find ec2 instance with name \"$HOST\"."
    print_usage
    exit 1
fi

IP=$(cat tmp.txt| jq -r '.Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp')
if [ "$IP" == "null" ]; then
    echo "Unable to find public ip address of ec2 instance \"$HOST\"."
    print_usage
    exit 1
else 
    echo "ec2 instance public IP: $IP"    
    rm tmp.txt
fi

# Check is host exist in known_host file
if [ -z "$(ssh-keygen -F $IP)" ]; then
    echo "Host doesn't exist in known_host file, add it..."
    ssh-keyscan $IP | grep ecdsa >> ~/.ssh/known_hosts
else 
    echo "Host exists in known_host file."
fi

# SSH into ec2
if [ -z "$COMMAND" ]; then
    ssh -i $KEY ec2-user@$IP
else 
    ssh -i $KEY ec2-user@$IP $COMMAND
fi

