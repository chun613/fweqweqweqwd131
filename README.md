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

1. Load Balancer
As the API entrypoint, load balancer can support more than 1000 request per sec and AWS will scale it up automatically depending on its load. 
The load balancer has a target group of ec2, make it easy for us to scale up the number of ec2 instance by spinning up new instance and register it to the target group. 

2. EC2 
A docker will be deployed to EC2 to handle the actual shorten url logic. In the setup script, user data is used to initially bootstrap the EC2 by installing docker and docker-compose. Also, 2 EC2 instance is being used to prevent single point of failure for the application. Of course, further scale up the number of EC2 instance is possible and is as simple as registering the new EC2 instance to the target group. 

3. DynamoDB  
Docker container will save the shorten and full url in dynamoDB. We can scale up DynamoDB by changing the read and write unit of it. 

### Usage
1. Run script to setup the entire infrastructure
``` bash
$./setup.sh [aws profile]
$ example
$ ./setup.sh default
```
This will setup load balancer, EC2 and DynamoDB by the given aws profile. 

2. At the end of the script, you will see an url similar to this, which is the endpoint of the service. Mark it down for later use.
```bash
http://url-shorten-lb-514807435.ap-southeast-1.elb.amazonaws.com/newurl
```

3. Wait for few minutes for the ec2 to complete the installation, and than run this to start the docker container in ec2
```bash
$ ./start-application.sh [aws profile]
$ example
$ ./start-application.sh default
```

4. Make shorten url request by calling this
```bash
$ curl -i -XPOST https://[LB_DNS]/prod/newurl -d '{"url":"https://google.com"}' -H 'Content-Type: application/json'
```

4. Get full url by calling this
```bash
$ curl -i http://[LB_DNS]/[SHORTEN_URL]
```

### API schema
There are 2 API endpoints exposed by the application:  
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
| app/      | the code for the docker container, written in Javascript |
| setup.sh  | Bash script to setup all the necessary cloud components |
| start-application.sh  | Script for starting up the docker container |
| bootstrap-ec2.txt  | user data file passed to ec2 during startup |
| trust-policy.json | IAM policy used by EC2 role |


### Enhancement
1. Make setup script re-runable 
2. Minimise the DynamoDB access permission for EC2
3. Use terraform to achieve all this
4. Provide domain name to load balancer
5. Use https instead of http
6. Include caching layer
7. Loop all eligible ec2 instance in start-application.sh instead of hard code each instance










