#!/bin/bash

format_date() {
    D=$1
    d=${D:0:2}
    m=${D:3:3}
    y=${D:7:4}
    H=${D:12:2}
    M=${D:15:2}
    S=${D:18:2}
    TS=$(date -d "$d-$m-$y $H:$M:$S" +%s)
    echo $TS
}

# Prepare environment
START_DATE="2019-06-10 00:00:00"
END_DATE="2019-06-19 23:59:59"
START_TS=$(date -d "$START_DATE" +%s)
END_TS=$(date -d "$END_DATE" +%s)
echo "Date range: $START_DATE - $END_DATE"
> log.txt

# Split log file into small batches
cat access.log | cut -d']' -f1 | cut -d' ' -f1,4 | sed 's/\[//g' > tmp.txt
echo "Split log file into batch of 5000 log"
split -d -l 5000 tmp.txt log_

# Find the first log file that has log within the given date
FIRST_FILE="$(ls log_* | head -n 1)"
for FILE in $(ls log_*); do
    DATE=$(head -n 1 $FILE | cut -d' ' -f2)
    TS=$(format_date $DATE)
    if [ $TS -ge $START_TS ] ; then
        break
    fi
    FIRST_FILE=$FILE
done

# Find the last log file has log within the given date
LAST_FILE="$(ls -r log_* | head -n 1)"
for FILE in $(ls -r log_*); do
    DATE=$(tail -n 1 $FILE | cut -d' ' -f2)
    TS=$(format_date $DATE)
    if [ $TS -le $END_TS ] ; then
        break
    fi
    LAST_FILE=$FILE
done

echo "Located logs within given time range are within file: $FIRST_FILE - $LAST_FILE"

# Only process files that have log within the given date
START_ID=$(echo $FIRST_FILE | cut -d'_' -f2)
END_ID=$(echo $LAST_FILE | cut -d'_' -f2)
for FILE in $(ls log_*); do

    # Get the number on the filename, see is it within the file range
    ID=$(echo $FILE | cut -d'_' -f2)
    if [ $ID -ge $START_ID ] && [ $ID -le $END_ID ]; then
        echo "Processing log file: $FILE"

        # Read the file line by line, find out log that is within time range
        cat $FILE | while read line ; do
            D=$(echo $line | cut -d' ' -f2)
            TS=$(format_date $D)
            if [ $TS -ge $START_TS ] && [ $TS -le $END_TS ]; then

                # Print the IP to another file for furthur process
                IP=$(echo $line | cut -d' ' -f1)
                echo $IP >> log.txt
            fi
        done
    fi 
done

# Find top N request IP
echo "Top 10 IP addresses that made the most requests:"
cat log.txt | sort | uniq -c | sort -nr | head -n 10

# Clean up
rm log_*
rm tmp*
