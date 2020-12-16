#!/bin/bash

> response.txt
for i in {1..100}; do
    RESP=$(curl -XPOST https://x9nnr5y9jd.execute-api.ap-southeast-1.amazonaws.com/prod/newurl -d "{\"url\":\"https://$i.com\"}" &)
    echo $RESP >> response.txt
done