#!/bin/bash

# Check for input file
if [ -z "$1" ]; then
    echo "Usage: ./sub2ip.sh <input_file.txt> [output_file.txt]"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Error: File '$1' not found."
    exit 1
fi

INPUT_FILE=$1
OUTPUT_FILE=$2

echo "Processing subdomains..."

# Use a while loop instead of 'for sub in $(cat ...)' 
# It's safer for files with weird spacing or hidden characters
while read -r sub; do
    if [ -n "$OUTPUT_FILE" ]; then
        # If output file is provided, strip text and append only IPs
        host "$sub" | grep "has address" | awk '{print $NF}' >> "$OUTPUT_FILE"
    else
        # Otherwise, just print the standard output to the screen
        host "$sub" | grep "has address"
    fi
done < "$INPUT_FILE"

if [ -n "$OUTPUT_FILE" ]; then
    echo "Done! Clean IPs saved to: $OUTPUT_FILE"
fi
