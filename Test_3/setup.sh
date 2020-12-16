#!/bin/bash

PROFILE="marcus.cheng"
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
    --profile marcus.cheng)
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

# ------------ Lambda ------------
echo "Setup lambda..."
echo "Check is lambda role exist..."
LAMBDA_ROLE_NAME="lambda-shorten-url-role"
LAMBDA_ROLE=$(aws iam get-role \
                --role-name $LAMBDA_ROLE_NAME \
                --profile $PROFILE)
if [ $? == 255 ]; then
    echo "Create execution role for lambda..."
    LAMBDA_ROLE=$(aws iam create-role \
                    --role-name $LAMBDA_ROLE_NAME \
                    --assume-role-policy-document file://trust-policy.json \
                    --profile $PROFILE) 
fi

LAMBDA_ROLE_ARN=$(echo $LAMBDA_ROLE | jq -r '.Role.Arn')
echo "Attach AWSLambdaBasicExecutionRole policy to $LAMBDA_ROLE_ARN"
aws iam attach-role-policy \
    --role-name $LAMBDA_ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
    --profile $PROFILE
echo "Attach AmazonDynamoDBFullAccess policy to $LAMBDA_ROLE_ARN"
aws iam attach-role-policy \
    --role-name $LAMBDA_ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
    --profile $PROFILE
echo "Lambda role name: arn: $LAMBDA_ROLE_NAME"

LAMBDA_FUNCTION="shorten-url"
zip $LAMBDA_FUNCTION.zip index.js
echo "Check is lambda function exist..."
RESP=$(aws lambda get-function \
        --function-name $LAMBDA_FUNCTION \
        --profile $PROFILE)
if [ $? == 255 ]; then
    echo "Lambda functon not exist, create function..."
    LAMBDA_ARN=$(aws lambda create-function \
                    --function-name $LAMBDA_FUNCTION \
                    --runtime nodejs12.x \
                    --handler index.handler \
                    --memory-size 128 \
                    --zip-file fileb://$LAMBDA_FUNCTION.zip \
                    --role $LAMBDA_ROLE_ARN \
                    --profile $PROFILE | jq -r '.FunctionArn')
else
    echo "Lambda function already exist, update functon..."
    LAMBDA_ARN=$(aws lambda update-function-code \
                    --function-name $LAMBDA_FUNCTION \
                    --zip-file fileb://$LAMBDA_FUNCTION.zip \
                    --profile $PROFILE | jq -r '.FunctionArn')
fi
echo "Lambda function, arn: $LAMBDA_ARN"

echo "Add permission to lambda, allow it to be called by api gateway..."
aws lambda add-permission \
    --function-name shorten-url \
    --principal apigateway.amazonaws.com \
    --statement-id apigateway \
    --action lambda:InvokeFunction \
    --profile $PROFILE

# ------------ API gateway ------------
echo "Create Rest API gateway: shorten-url..."
REST_API_ID=$(aws apigateway create-rest-api \
                --name 'shorten-url' \
                --description 'Restful API to shorten url' \
                --profile $PROFILE | jq -r '.id')
ROOT_RES_ID=$(aws apigateway get-resources \
                --rest-api-id $REST_API_ID \
                --profile $PROFILE | jq -r '.items[] | select(.path == "\/") | .id')

# Create API endpoint: GET "/"
echo "Setup API endpoint GET / ..."
PATH_RES_ID=$(aws apigateway create-resource \
                --rest-api-id $REST_API_ID \
                --parent-id $ROOT_RES_ID \
                --path-part '{proxy+}' \
                --profile $PROFILE | jq -r '.id')
echo "aws apigateway put-method"
aws apigateway put-method \
    --rest-api-id $REST_API_ID \
    --resource-id $PATH_RES_ID \
    --http-method GET \
    --authorization-type NONE \
    --profile $PROFILE
echo "aws apigateway put-integration"
aws apigateway put-integration \
    --rest-api-id $REST_API_ID \
    --resource-id $PATH_RES_ID \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:$REGION:lambda:path//2015-03-31/functions/$LAMBDA_ARN/invocations" \
    --profile $PROFILE

# Create API endpoint: POST "/newurl"
echo "Setup API endpoint POST /newurl ..."
PATH_RES_ID=$(aws apigateway create-resource \
                --rest-api-id $REST_API_ID \
                --parent-id $ROOT_RES_ID \
                --path-part 'newurl' \
                --profile $PROFILE | jq -r '.id')
echo "aws apigateway put-method"
aws apigateway put-method \
    --rest-api-id $REST_API_ID \
    --resource-id $PATH_RES_ID \
    --http-method POST \
    --authorization-type NONE \
    --profile $PROFILE
echo "aws apigateway put-integration"
aws apigateway put-integration \
    --rest-api-id $REST_API_ID \
    --resource-id $PATH_RES_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:$REGION:lambda:path//2015-03-31/functions/$LAMBDA_ARN/invocations" \
    --profile $PROFILE

# Create deployment
echo "Deploy the API endpoint"
STAGE="prod"
aws apigateway create-deployment \
    --rest-api-id $REST_API_ID \
    --stage-name $STAGE \
    --profile $PROFILE

# ------------ Post setup ------------
# Lambda set env var
echo "Update lambda environment variable..."
aws lambda update-function-configuration \
    --function-name $LAMBDA_FUNCTION \
    --environment Variables={REST_API_ID=$REST_API_ID} \
    --profile $PROFILE


echo -e "\n\nExample usage:"
echo "curl -i -XPOST https://$REST_API_ID.execute-api.$REGION.amazonaws.com/$STAGE/newurl -d '{\"url\":\"https://google.com\"}'"