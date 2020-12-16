#!/bin/bash

# http://ip-api.com/batch?fields=country,countryCode
# API documentation: https://ip-api.com/docs/api:batch
# Example request body: '["208.80.152.201", "91.198.174.192"]'
check_ip_geolocation() {
    # Construct request body
    BATCH_IPS=$1
    BODY="["
    for IP in ${BATCH_IPS[@]}; do
        BODY+='"'$IP'",'
    done
    BODY=$(echo $BODY | sed 's/.$//') # Remove last ","
    BODY+="]"

    # Make request to ip-api.com, store the result as a list in a file
    curl http://ip-api.com/batch?fields=country --data $BODY > tmp.txt
    cat tmp.txt | jq -r '.[] | .country' >> country.txt
}

install_tools() {
    if $(command -v jq > /dev/null); then
        echo "JQ installed, continue."
    else
        echo "JQ does not exist, install it now."
        sudo yum install jq -y
    fi
}

# Prepare environment
install_tools
> tmp.txt
> country.txt

# Get only the ip field from the access.log file
cat "access.log" | cut -d' ' -f1 | sort | uniq > ip.txt
LINE=$(cat ip.txt | wc -l)
TOTAL_BATCH=$((LINE/100))
echo "Total number of batch: ${TOTAL_BATCH}"

# Restriction from ip-api.com, max ip address allowed in batch request is 100
# Split the ip address list to batch of 100
BATCH_ID=1
COUNTER=1
BATCH_IPS=()
for IP in $(cat ip.txt); do
    if [ $COUNTER -ge 100 ]; then
        # Retriction from ip-api.com, only allow up to 45 api calls per minutes
        # Add sleep time between calls to prevent limit exceed
        echo -e "\nQuery to retrieve ip geolocation, batch: ${BATCH_ID}"
        check_ip_geolocation $BATCH_IPS

        # Reset value
        COUNTER=1
        BATCH_IPS=()
        BATCH_ID=$((BATCH_ID + 1))
        sleep 5
    fi
    BATCH_IPS+=($IP)
    COUNTER=$((COUNTER + 1))
done

# Sort the country list and get the result
echo -e "\n\nCountry with most request:"
cat country.txt | sort | uniq -c | sort -nr | head -n 1 | cut -d' ' -f2

# Clean up
rm tmp.txt
rm country.txt
rm ip.txt