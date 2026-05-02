#!/bin/bash

# Check for input file
if [ -z "$1" ]; then
    echo "Usage: ./lookup.sh <input_file.txt> [output_file.txt]"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Error: File '$1' not found."
    exit 1
fi

INPUT_FILE=$1
OUTPUT_FILE=$2

# Only print "Processing" if we aren't piping output to a file, 
# or use stderr to keep stdout clean for IPs only.
echo "Processing subdomains..." >&2

while read -r sub; do
    # Get the IP, then use awk to print only the last field (the IP)
    IP=$(host "$sub" | grep "has address" | awk '{print $NF}')
    
    # If an IP was found (not empty)
    if [ -n "$IP" ]; then
        if [ -n "$OUTPUT_FILE" ]; then
            echo "$IP" >> "$OUTPUT_FILE"
        else
            echo "$IP"
        fi
    fi
done < "$INPUT_FILE"

if [ -n "$OUTPUT_FILE" ]; then
    echo "Done! Clean IPs saved to: $OUTPUT_FILE" >&2
fi
