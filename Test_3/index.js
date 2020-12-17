var AWS = require('aws-sdk');
let region = process.env.AWS_REGION;
AWS.config.update({region: region});
var restApiId = process.env.REST_API_ID

exports.handler = async (event) => {
    console.log(`event.path: ${event.path}`);
    console.log(`event.httpMethod: ${event.httpMethod}`);
    console.log(`event.body: ${event.body}`);
    var docClient = new AWS.DynamoDB.DocumentClient();
    
    if (event.httpMethod == "GET") {
        let path = event.path;
        path = path.replace('/', '');
        let id = UrlShortener.decode(path);
        console.log(`Decode shortUrl, path: ${path}, id: ${id}`);
        let data = await findById(docClient, id);
        if (data.Item !== undefined) {
            return {
                statusCode: 302,
                headers: {
                    location: data.Item.long_url
                }
            }
        }
        return {
            statusCode: 404
        }
    } else if (event.httpMethod == "POST") {
        let body = (typeof event.body === 'string') ? JSON.parse(event.body): event.body;
        let longUrl = body.url;
        console.log(`Shorten url: ${longUrl}, ${body}`);
        if (longUrl === undefined) {
            return {
                statusCode: 400   
            }
        }

        let data = await findByLongUrl(docClient, longUrl);
        console.log(`findByLongUrl: ${JSON.stringify(data)}`);
        if (data.Count > 0) {
            let shortUrl = data.Items[0].short_url;
            console.log(`Url found in db: ${shortUrl}`);
            return  {
                statusCode: 200,
                body: JSON.stringify({
                    url: longUrl,
                    shortenUrl: `https://${restApiId}.execute-api.${region}.amazonaws.com/prod/${shortUrl}`
                })
            }
        }

        console.log(`Url not found in db, create short url`);
        let count = await getCounter(docClient);
        let shortUrl = UrlShortener.encode(count);
        await saveShortUrl(docClient, count, shortUrl, longUrl);
        console.log(`Short url saved, id: ${count}, shortUrl: ${shortUrl}, longUrl: ${longUrl}`);
        return {
            statusCode: 200,
            body: JSON.stringify({
                url: longUrl,
                shortenUrl: `https://${restApiId}.execute-api.${region}.amazonaws.com/prod/${shortUrl}`
            })
        }
    }

    return {
        statusCode: 400
    };
};

async function findById(docClient, id) {
    const params = {
        TableName: 'shorten_url',
        Key:{
            "id": id.toString()
        }
    };
    return new Promise((resolve, reject) => {
        docClient.get(params, (err, data) => {
            if (err) {
                console.log("Error", err);
                reject();
            } else {
                console.log("Success", data);
                resolve(data);
            }
        });
    });    
}

async function findByLongUrl(ddb, longUrl) {
    const params = {
        TableName: 'shorten_url',
        ExpressionAttributeValues: {
            ":a": longUrl
        },
        FilterExpression: "long_url = :a"
    };
    return new Promise((resolve, reject) => {
        ddb.scan(params, (err, data) => {
            if (err) {
                console.log("Error", err);
                reject();
            } else {
                resolve(data);
            }
        });
    });
}

async function getCounter(ddb) {
    const params = {
        TableName: 'counter',
        Key:{
            "ID": "1"
        },
        ExpressionAttributeValues:{
            ":p": 1
        },
        UpdateExpression: "set C = C + :p",
        ReturnValues:"UPDATED_NEW"
    }
    return new Promise((resolve, reject) => {
        ddb.update(params, (err, data) => {
            if (err) {
                console.error("Unable to add item. Error JSON:", JSON.stringify(err, null, 2));
                reject();
            } else {
                resolve(data.Attributes.C);
            }
        });
    });
}

async function saveShortUrl(docClient, id, shortUrl, longUrl) {
    const params = {
        TableName: 'shorten_url',
        Item: {
            "id": id.toString(),
            "short_url": shortUrl,
            "long_url": longUrl
        }
    }
    return new Promise((resolve, reject) => {
        docClient.put(params, (err, data) => {
            if (err) {
                console.error("Unable to add item. Error JSON:", JSON.stringify(err, null, 2));
                reject();
            } else {
                resolve();
            }
        });
    });
}

var UrlShortener = new function() {
	var _alphabet = '23456789bcdfghjkmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ-_',
		_base = _alphabet.length;

	this.encode = function(num) {
		var str = '';
		while (num > 0) {
			str = _alphabet.charAt(num % _base) + str;
			num = Math.floor(num / _base);
		}
		return str;
	};

	this.decode = function(str) {
		var num = 0;
		for (var i = 0; i < str.length; i++) {
			num = num * _base + _alphabet.indexOf(str.charAt(i));
		}
		return num;
	};
};

console.log(UrlShortener.encode(2));