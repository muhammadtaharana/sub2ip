#!/bin/bash

# sub2ip - Subdomain to IP resolution engine
# Version 2.1: Fixed for Kali Linux with all bugs resolved
# Multi-threading, DNS record filtering, multiple resolvers

set -o pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
THREADS=4
RECORD_TYPE="A"
RESOLVER=""
OUTPUT_FILE=""
INPUT_FILE=""
VERBOSE=0
LOCK_FILE="/tmp/sub2ip_$$_lock"

# Cleanup on exit
cleanup() {
    rm -f "$LOCK_FILE" 2>/dev/null
}
trap cleanup EXIT

# Display usage
show_usage() {
    echo -e "${GREEN}sub2ip v2.1${NC} - Subdomain to IP Resolution Engine (Kali Linux)"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "    sub2ip.sh <input_file.txt> [OPTIONS]"
    echo ""
    echo -e "${YELLOW}Required:${NC}"
    echo "    input_file.txt          File containing subdomains (one per line)"
    echo ""
    echo -e "${YELLOW}Optional Arguments:${NC}"
    echo "    -o, --output FILE       Output file for clean results (default: screen)"
    echo "    -t, --threads NUM       Number of parallel threads (default: 4, max: 16)"
    echo "    -r, --record TYPE       DNS record type to query (default: A)"
    echo "                            Supported: A, AAAA, CNAME, MX, NS, TXT, SOA, ANY"
    echo "    -s, --server SERVER     Custom DNS server (e.g., 8.8.8.8)"
    echo "    -v, --verbose           Enable verbose output"
    echo "    -h, --help              Display this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "    # Resolve to screen with 4 threads"
    echo "    sub2ip.sh subdomains.txt"
    echo ""
    echo "    # Save IPs to file with 8 threads"
    echo "    sub2ip.sh subdomains.txt -o resolved_ips.txt -t 8"
    echo ""
    echo "    # Query AAAA records (IPv6) with Google DNS"
    echo "    sub2ip.sh subdomains.txt -r AAAA -s 8.8.8.8"
    echo ""
    echo "    # Query CNAME records and save to file"
    echo "    sub2ip.sh subdomains.txt -r CNAME -o cnames.txt"
    echo ""
    echo "    # Verbose output with custom DNS server"
    echo "    sub2ip.sh subdomains.txt -s 1.1.1.1 -v"
}

# Parse arguments
# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                if [ -z "$OUTPUT_FILE" ]; then
                    echo -e "${RED}Error: Output file path cannot be empty${NC}"
                    exit 1
                fi
                shift 2
                ;;
            -t|--threads)
                THREADS="$2"
                if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [ "$THREADS" -lt 1 ] || [ "$THREADS" -gt 16 ]; then
                    echo -e "${RED}Error: Threads must be a number between 1 and 16${NC}"
                    exit 1
                fi
                shift 2
                ;;
            -r|--record)
                RECORD_TYPE="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
                if ! [[ "$RECORD_TYPE" =~ ^(A|AAAA|CNAME|MX|NS|TXT|SOA|ANY)$ ]]; then
                    echo -e "${RED}Error: Unsupported record type: $RECORD_TYPE${NC}"
                    echo -e "${YELLOW}Supported: A, AAAA, CNAME, MX, NS, TXT, SOA, ANY${NC}"
                    exit 1
                fi
                shift 2
                ;;
            -s|--server)
                RESOLVER="$2"
                if [ -z "$RESOLVER" ]; then
                    echo -e "${RED}Error: DNS server cannot be empty${NC}"
                    exit 1
                fi
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            *)
                if [ -z "$INPUT_FILE" ]; then
                    INPUT_FILE="$1"
                fi
                shift
                ;;
        esac
    done
}

# Validate input
validate_input() {
    if [ -z "$INPUT_FILE" ]; then
        echo -e "${RED}Error: Input file is required${NC}"
        show_usage
        exit 1
    fi

    if [ ! -f "$INPUT_FILE" ]; then
        echo -e "${RED}Error: File '$INPUT_FILE' not found${NC}"
        exit 1
    fi

    # Check for required DNS tools
    if ! command -v dig &> /dev/null && ! command -v host &> /dev/null; then
        echo -e "${RED}Error: Neither 'dig' nor 'host' found${NC}"
        echo "Please install dnsutils: sudo apt-get install dnsutils"
        exit 1
    fi

    # Check for GNU parallel
    if ! command -v parallel &> /dev/null; then
        echo -e "${YELLOW}Warning: GNU Parallel not found, using sequential processing${NC}"
        echo -e "${YELLOW}Install for better performance: sudo apt-get install parallel${NC}"
    fi
}

# Validate DNS server
validate_resolver() {
    if [ -z "$RESOLVER" ]; then
        return 0
    fi

    # Validate IP format (basic check)
    if ! [[ "$RESOLVER" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}Error: Invalid DNS server format: $RESOLVER${NC}"
        echo "Expected format: XXX.XXX.XXX.XXX"
        exit 1
    fi
}

# Detect best DNS tool available
detect_dns_tool() {
    if command -v dig &> /dev/null; then
        echo "dig"
    elif command -v host &> /dev/null; then
        echo "host"
    else
        echo "none"
    fi
}

# Query DNS using dig or host
query_dns() {
    local subdomain="$1"
    local tool="$2"
    local output=""

    case "$tool" in
        dig)
            if [ -n "$RESOLVER" ]; then
                output=$(dig "@$RESOLVER" "$subdomain" "$RECORD_TYPE" +short 2>/dev/null)
            else
                output=$(dig "$subdomain" "$RECORD_TYPE" +short 2>/dev/null)
            fi
            ;;
        host)
            if [ -n "$RESOLVER" ]; then
                output=$(host -t "$RECORD_TYPE" "$subdomain" "$RESOLVER" 2>/dev/null)
            else
                output=$(host -t "$RECORD_TYPE" "$subdomain" 2>/dev/null)
            fi
            ;;
    esac

    if [ -n "$output" ]; then
        echo "$output"
    else
        if [ $VERBOSE -eq 1 ]; then
            echo -e "${RED}[!] Failed to resolve: $subdomain${NC}" >&2
        fi
    fi
}

# Filter results based on record type and DNS tool
filter_results() {
    local output="$1"
    local type="$2"
    local tool="$3"
    
    case "$tool" in
        host)
            # Filter for host command output
            case "$type" in
                A)
                    echo "$output" | grep "has address" | awk '{print $NF}'
                    ;;
                AAAA)
                    echo "$output" | grep "has IPv6 address" | awk '{print $NF}'
                    ;;
                CNAME)
                    echo "$output" | grep "is an alias for" | awk '{print $NF}' | sed 's/\.$//'
                    ;;
                MX)
                    echo "$output" | grep "mail is handled by" | awk '{print $NF}' | sed 's/\.$//'
                    ;;
                NS)
                    echo "$output" | grep "nameserver" | awk '{print $NF}' | sed 's/\.$//'
                    ;;
                TXT)
                    echo "$output" | grep "descriptive text" | cut -d'"' -f2
                    ;;
                SOA)
                    echo "$output" | grep "start of authority"
                    ;;
                ANY)
                    echo "$output"
                    ;;
            esac
            ;;
        nslookup)
            # Filter for nslookup output
            case "$type" in
                A)
                    # Extract IPv4 - start after "Name:" line and get first IP
                    echo "$output" | awk '/^Name:/{p=1} p' | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -1
                    ;;
                AAAA)
                    # Extract IPv6 addresses after Name line
                    echo "$output" | awk '/^Name:/{p=1} p' | grep -oE '([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}' | head -1
                    ;;
                *)
                    echo "$output" | grep -E "(CNAME|MX|NS|TXT)" | head -1
                    ;;
            esac
            ;;
        powershell)
            # Filter for PowerShell Resolve-DnsName output
            case "$type" in
                A)
                    echo "$output" | grep -i "ipaddress" | awk '{print $NF}'
                    ;;
                *)
                    echo "$output" | grep -i "$type" | head -1
                    ;;
            esac
            ;;
        *)
            echo "$output"
            ;;
    esac
}

# Process individual subdomain
process_subdomain() {
    local subdomain="$1"
    local output_file="$2"
    local dns_tool="$3"
    local record_type="$4"

    # Skip empty lines
    if [ -z "$subdomain" ] || [[ "$subdomain" =~ ^[[:space:]]*$ ]]; then
        return
    fi

    if [ $VERBOSE -eq 1 ]; then
        echo -e "${YELLOW}[*] Querying: $subdomain${NC}" >&2
    fi

    local output
    output=$(query_dns "$subdomain" "$dns_tool")

    if [ -n "$output" ]; then
        local result
        result=$(filter_results "$output" "$record_type" "$dns_tool")

        if [ -n "$result" ]; then
            write_result "${GREEN}${subdomain}${NC} -> ${result}" "$output_file"
        fi
    fi
}

# Export functions for parallel
export -f query_dns filter_results process_subdomain write_result
export RECORD_TYPE RESOLVER VERBOSE LOCK_FILE

# Main execution
main() {
    parse_args "$@"
    validate_input
    validate_resolver

    # Detect DNS tool
    DNS_TOOL=$(detect_dns_tool)
    
    if [ "$DNS_TOOL" = "none" ]; then
        echo -e "${RED}Error: No DNS lookup tool found${NC}"
        echo "Please install one of the following:"
        echo "  - host (dnsutils on Linux, bind on macOS)"
        echo "  - nslookup (built-in on Windows/macOS)"
        echo "  - PowerShell (built-in on Windows)"
        exit 1
    fi

    # Clear output file if it exists
    if [ -n "$OUTPUT_FILE" ]; then
        > "$OUTPUT_FILE"
    fi

    echo -e "${GREEN}[+] Starting sub2ip resolution engine${NC}"
    echo -e "${YELLOW}[*] Input file: $INPUT_FILE${NC}"
    echo -e "${YELLOW}[*] DNS Tool: $DNS_TOOL${NC}"
    echo -e "${YELLOW}[*] Record type: $RECORD_TYPE${NC}"
    echo -e "${YELLOW}[*] Threads: $THREADS${NC}"
    [ -n "$RESOLVER" ] && echo -e "${YELLOW}[*] DNS Server: $RESOLVER${NC}"
    [ -n "$OUTPUT_FILE" ] && echo -e "${YELLOW}[*] Output file: $OUTPUT_FILE${NC}"
    echo ""

    # Process with GNU Parallel if available, otherwise use background jobs
    if command -v parallel &> /dev/null; then
        cat "$INPUT_FILE" | parallel -j "$THREADS" process_subdomain {} "$OUTPUT_FILE" "$DNS_TOOL" "$RECORD_TYPE"
    else
        # Use background jobs for systems without GNU Parallel
        local counter=0
        while IFS= read -r subdomain || [ -n "$subdomain" ]; do
            # Skip empty/whitespace lines
            [[ -z "$subdomain" || "$subdomain" =~ ^[[:space:]]*$ ]] && continue

            if [ $VERBOSE -eq 1 ]; then
                echo -e "${YELLOW}[*] Querying: $subdomain${NC}" >&2
            fi

            # Process in background
            (
                output=$(query_dns "$subdomain" "$DNS_TOOL")
                if [ -n "$output" ]; then
                    result=$(filter_results "$output" "$RECORD_TYPE" "$DNS_TOOL")
                    if [ -n "$result" ]; then
                        if [ -n "$OUTPUT_FILE" ]; then
                            echo "$result" >> "$OUTPUT_FILE"
                        else
                            echo -e "${GREEN}${subdomain}${NC} -> ${result}"
                        fi
                    fi
                fi
            ) &

            # Thread management without wait -n (compatible with bash <5.1)
            counter=$((counter + 1))
            if [ $counter -ge "$THREADS" ]; then
                wait  # Wait for any background job
                counter=0
            fi
        done < "$INPUT_FILE"

        # Wait for remaining jobs
        wait
    fi

    echo ""
    if [ -n "$OUTPUT_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
        local lines
        lines=$(wc -l < "$OUTPUT_FILE")
        echo -e "${GREEN}[+] Done! $lines results saved to: $OUTPUT_FILE${NC}"
    else
        echo -e "${GREEN}[+] Resolution complete!${NC}"
    fi
}

# Run main
main "$@"
