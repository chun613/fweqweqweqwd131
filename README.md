# Crypto Test 
## Test 1 - Access Log Aanlytics 
Located inside `Test_1` folder.  
Question 1: total_http_request.sh  
Question 2: top_request_market.sh  
Question 3: top_request_origin.sh  

## Test 2 - AWS API Programming 
Located inside `Test_2` folder.  

### Usage
```bash
$ ./awssh.sh [host name] [key location] [aws profile]
Example
$ ./awssh.sh host_1 ~/.ssh/host_1.pem default
```

### Limitation
This approach will potentially expose to MITM attack if at the moment when we run this script we are being attacked. 

## Test 3 - System Design and Implmentation 
Located inside `Test_3` folder.   

### System design 
This system is composed by 3 major aws services:  

1. API Gateway  
API gateway is used to serve users' requests. Received requests will pass through to Lambda function for shortening the url or getting the full url.   
With API gateway, we can easily manage the entry point of the API, and adding authentication and caching layer in the future.   
By default, API gateway allows for up to 10,000 requests per second. And as it is managed by AWS, we don't have to worry that much about the availability. In case of further increasing the accepted number of request per second, we can add load balancer in front of api gateway to further scale the infrastructure. 

2. Lambda  
A lambda function will be triggered upon user makes request to API gateway. Depending on the http method, lambda will either shorten the given url, or return a full url.  
Since the logic itself is quite simple and fast to execute, using lambda is suitable in this case where we don't have to worry about the maintenance and provisioning of the underlying infrastructure.  
By default, lambda supports up to 1,000 concurrent call. We can increase this limit by requesting a quota increase. To further scale the function execution, we can use other AWS services like ECS that can spin up hundreds of containers to handled heavy loads.

3. DynamoDB  
Lambda function will store the shorten and full url in dynamoDB. 
We can scale up DynamoDB by changing the read and write unit of it. 

### Usage
1. Run `./setup.sh [aws profile]`, e.g. `./setup.sh default`
This will setup dynamodb, lambda and api gateway by the given aws profile. 


2. At the end of the script, you will see an url similar to this. Which is the endpoint of the service.
```bash
https://[API_GATEWAY_RESOURCE_ID].execute-api.ap-southeast-1.amazonaws.com/prod/newurl
```

3. Make shorten url request by calling this
```bash
$ curl -i -XPOST https://[API_GATEWAY_RESOURCE_ID].execute-api.ap-southeast-1.amazonaws.com/prod/newurl -d '{"url":"https://google.com"}'
```

4. Get full url by calling this
```bash
$ https://[API_GATEWAY_RESOURCE_ID].execute-api.ap-southeast-1.amazonaws.com/prod/[SHORTEN_URL]
```

### API schema
There are 2 API endpoints exposed by API gateway:  
```yaml
Path:  
  /newurl:  
    post:  
      summary: Shorten the given url
      parameters: 
        - name: url
          type: string
          required: true
      responses:
        200:
          description: ok
        400:
          description: parameter not provided
    
  /{shorten_url}:
    get:
      summary: Redirect to stored url by passing shorten url
      parameters:
        - name: shorten_url
          type: string
          required: true
      responses:
        302:
          description: redirect to the stored url
        404:
          description: shorten url not found
```

### Files
| Name      | Description |  
| --------- | ----------- |  
| index.js  | the code for lambda function, written in Javascript |
| setup.sh  | Bash script to setup all the necessary cloud components |
| trust-policy.json | IAM policy used by lambda role |

### Enhancement
1. Make setup script re-runable 
2. Minimise the DynamoDB access permission for lambda function
3. Chek request parameters at API gateway level
4. Use terraform to achieve all this
6. Provide domain name instead of using api gateway url
7. Include caching layer

### Alternative
As mentioned in system design section, an approach to further scale up the infrastructure is to setup load balancer in front of api gateway, and replace lambda function by ECS that can spin up many containers to support the load. Futhurmore, we can consider to use cloudfront to cache some of the requests to offload the lambda/ECS and DynamoDB.