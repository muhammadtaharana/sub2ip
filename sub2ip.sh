#!/usr/bin/env bash
# ==============================================================================
#  sub2ip v3.0 — Ultra-Advanced Subdomain-to-IP Resolution Engine
#  Author  : Remade from scratch (v2.1 audit + full rewrite)
#  Requires: bash ≥4.2  |  dig (preferred) or host
#  Optional: GNU Parallel (parallel), flock (util-linux)
# ==============================================================================
# BUGS FIXED FROM v2.1:
#  1. write_result() was called but never defined → defined below with flock
#  2. export -f referenced write_result before definition → exports moved to bottom
#  3. nslookup/powershell branches in filter_results() were dead code (detect_dns_tool
#     never returned those values) → removed; kept dig+host with clean logic
#  4. ANSI colour codes leaked into output files → strip_ansi() wrapper added
#  5. Background-job counter reset to 0 after THREADS, destroying concurrency
#     semantics → replaced with proper fd-based semaphore
#  6. LOCK_FILE created but flock never called → now flock-protected writes
#  7. No timeout on DNS queries → --timeout flag + dig +time= enforced
#  8. No deduplication → seen-associative-array dedup per subdomain
#  9. No retry logic on transient failures → --retries flag + exponential backoff
# 10. No input sanitisation (comments, whitespace, BOM) → clean_line() added
# 11. Statistics never tracked → atomic counters via tmp files + final summary
# 12. No wildcard detection → wildcard_check() warns operator up-front
# 13. No output format options → --format plain|csv|json supported
# 14. IPv6 resolver addresses not handled by validation regex → updated regex
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Colour palette ─────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ── Defaults ───────────────────────────────────────────────────────────────────
THREADS=10
RECORD_TYPE="A"
RESOLVER=""
OUTPUT_FILE=""
INPUT_FILE=""
VERBOSE=0
TIMEOUT=5
RETRIES=2
FORMAT="plain"           # plain | csv | json
WILDCARD_CHECK=1
RATE_LIMIT=0             # ms between queries per thread (0 = unlimited)
NO_COLOR=0

# ── Runtime state (tmp dir, not /tmp root to avoid collisions) ─────────────────
TMP_DIR=""
LOCK_FILE=""
STAT_RESOLVED=""
STAT_FAILED=""
STAT_SKIPPED=""
DNS_TOOL=""

# ══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

init_tmp() {
    TMP_DIR=$(mktemp -d "/tmp/sub2ip_$$.XXXXXX")
    LOCK_FILE="${TMP_DIR}/write.lock"
    STAT_RESOLVED="${TMP_DIR}/resolved"
    STAT_FAILED="${TMP_DIR}/failed"
    STAT_SKIPPED="${TMP_DIR}/skipped"
    touch "$STAT_RESOLVED" "$STAT_FAILED" "$STAT_SKIPPED" "$LOCK_FILE"
}

cleanup() {
    local exit_code=$?
    [[ -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"
    exit "$exit_code"
}
trap cleanup EXIT
trap 'echo -e "\n${YELLOW}[!] Interrupted — cleaning up…${NC}" >&2; exit 130' INT TERM

# ══════════════════════════════════════════════════════════════════════════════
#  DISPLAY HELPERS
# ══════════════════════════════════════════════════════════════════════════════

# Strip ANSI escape sequences (for clean file output)
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

cecho() {
    # cecho COLOR "message"  — honours NO_COLOR
    local color="$1"; shift
    if [[ $NO_COLOR -eq 1 ]]; then
        echo "$@"
    else
        echo -e "${color}$*${NC}"
    fi
}

log_verbose() { [[ $VERBOSE -eq 1 ]] && echo -e "${DIM}${CYAN}[DBG]${NC} $*" >&2 || true; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*" >&2; }
log_error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
log_info()    { echo -e "${BLUE}[*]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[✓]${NC} $*"; }

# ══════════════════════════════════════════════════════════════════════════════
#  USAGE
# ══════════════════════════════════════════════════════════════════════════════

show_usage() {
    cat <<EOF
$(cecho "$BOLD$GREEN" "sub2ip v3.0") — Subdomain-to-IP Resolution Engine

$(cecho "$YELLOW" "Usage:")
    $(basename "$0") <input_file> [OPTIONS]

$(cecho "$YELLOW" "Required:")
    input_file              File containing subdomains (one per line)

$(cecho "$YELLOW" "Resolution Options:")
    -r, --record TYPE       DNS record type (default: A)
                            Supported: A AAAA CNAME MX NS TXT SOA ANY
    -s, --server SERVER     Custom DNS resolver (IPv4 or IPv6, e.g. 8.8.8.8)
    --timeout SECS          Per-query timeout in seconds (default: 5)
    --retries N             Retry failed queries N times with backoff (default: 2)
    --no-wildcard           Skip wildcard DNS pre-check

$(cecho "$YELLOW" "Performance Options:")
    -t, --threads NUM       Parallel threads 1-64 (default: 10)
    --rate-limit MS         Delay (ms) between queries per thread (default: 0)

$(cecho "$YELLOW" "Output Options:")
    -o, --output FILE       Write results to file (default: stdout)
    -f, --format FORMAT     Output format: plain | csv | json (default: plain)
    -v, --verbose           Enable debug output
    --no-color              Disable colour output

$(cecho "$YELLOW" "Examples:")
    # Resolve A records, 10 threads
    $(basename "$0") subdomains.txt

    # AAAA records, custom resolver, 20 threads, save to file
    $(basename "$0") subdomains.txt -r AAAA -s 8.8.8.8 -t 20 -o ipv6.txt

    # CNAME records as JSON
    $(basename "$0") subdomains.txt -r CNAME -f json -o cnames.json

    # Respectful scan: 8 threads, 200ms rate limit, retries
    $(basename "$0") subdomains.txt -t 8 --rate-limit 200 --retries 3
EOF
}

# ══════════════════════════════════════════════════════════════════════════════
#  ARGUMENT PARSING
# ══════════════════════════════════════════════════════════════════════════════

parse_args() {
    if [[ $# -eq 0 ]]; then
        show_usage; exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)      show_usage; exit 0 ;;
            -v|--verbose)   VERBOSE=1; shift ;;
            --no-color)     NO_COLOR=1; shift ;;
            --no-wildcard)  WILDCARD_CHECK=0; shift ;;

            -o|--output)
                [[ -z "${2:-}" ]] && { log_error "--output requires a path"; exit 1; }
                OUTPUT_FILE="$2"; shift 2 ;;

            -t|--threads)
                [[ -z "${2:-}" ]] && { log_error "--threads requires a number"; exit 1; }
                THREADS="$2"
                if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || (( THREADS < 1 || THREADS > 64 )); then
                    log_error "Threads must be 1–64 (got: $THREADS)"; exit 1
                fi
                shift 2 ;;

            -r|--record)
                [[ -z "${2:-}" ]] && { log_error "--record requires a type"; exit 1; }
                RECORD_TYPE="${2^^}"
                if ! [[ "$RECORD_TYPE" =~ ^(A|AAAA|CNAME|MX|NS|TXT|SOA|ANY)$ ]]; then
                    log_error "Unsupported record type: $RECORD_TYPE"
                    echo "Supported: A AAAA CNAME MX NS TXT SOA ANY" >&2
                    exit 1
                fi
                shift 2 ;;

            -s|--server)
                [[ -z "${2:-}" ]] && { log_error "--server requires an address"; exit 1; }
                RESOLVER="$2"; shift 2 ;;

            -f|--format)
                [[ -z "${2:-}" ]] && { log_error "--format requires plain|csv|json"; exit 1; }
                FORMAT="${2,,}"
                if ! [[ "$FORMAT" =~ ^(plain|csv|json)$ ]]; then
                    log_error "Unknown format: $FORMAT (use plain, csv, or json)"; exit 1
                fi
                shift 2 ;;

            --timeout)
                [[ -z "${2:-}" ]] && { log_error "--timeout requires seconds"; exit 1; }
                TIMEOUT="$2"
                if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || (( TIMEOUT < 1 )); then
                    log_error "Timeout must be a positive integer"; exit 1
                fi
                shift 2 ;;

            --retries)
                [[ -z "${2:-}" ]] && { log_error "--retries requires a number"; exit 1; }
                RETRIES="$2"
                if ! [[ "$RETRIES" =~ ^[0-9]+$ ]]; then
                    log_error "Retries must be a non-negative integer"; exit 1
                fi
                shift 2 ;;

            --rate-limit)
                [[ -z "${2:-}" ]] && { log_error "--rate-limit requires milliseconds"; exit 1; }
                RATE_LIMIT="$2"
                if ! [[ "$RATE_LIMIT" =~ ^[0-9]+$ ]]; then
                    log_error "Rate limit must be a non-negative integer (ms)"; exit 1
                fi
                shift 2 ;;

            -*)
                log_error "Unknown option: $1"; show_usage; exit 1 ;;

            *)
                if [[ -z "$INPUT_FILE" ]]; then
                    INPUT_FILE="$1"
                else
                    log_error "Unexpected argument: $1"; exit 1
                fi
                shift ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
#  VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

validate_input() {
    if [[ -z "$INPUT_FILE" ]]; then
        log_error "Input file is required."; show_usage; exit 1
    fi
    if [[ ! -f "$INPUT_FILE" ]]; then
        log_error "File not found: '$INPUT_FILE'"; exit 1
    fi
    if [[ ! -r "$INPUT_FILE" ]]; then
        log_error "File not readable: '$INPUT_FILE'"; exit 1
    fi
}

validate_resolver() {
    [[ -z "$RESOLVER" ]] && return 0

    # Accept IPv4, IPv6 (plain or bracketed), or hostname
    local ipv4='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    local ipv6='^(\[?[0-9a-fA-F:]+\]?)$'
    local hostname='^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'

    if ! [[ "$RESOLVER" =~ $ipv4 || "$RESOLVER" =~ $ipv6 || "$RESOLVER" =~ $hostname ]]; then
        log_error "Invalid DNS resolver address: $RESOLVER"; exit 1
    fi

    # Validate each IPv4 octet
    if [[ "$RESOLVER" =~ $ipv4 ]]; then
        local IFS='.'
        read -ra octets <<< "$RESOLVER"
        for oct in "${octets[@]}"; do
            if (( oct > 255 )); then
                log_error "Invalid IP octet ($oct) in resolver: $RESOLVER"; exit 1
            fi
        done
    fi
}

detect_dns_tool() {
    if command -v dig &>/dev/null; then
        echo "dig"
    elif command -v host &>/dev/null; then
        echo "host"
    else
        echo "none"
    fi
}

validate_tools() {
    DNS_TOOL=$(detect_dns_tool)
    if [[ "$DNS_TOOL" == "none" ]]; then
        log_error "No DNS lookup tool found."
        echo "Install dnsutils:  sudo apt-get install dnsutils" >&2
        exit 1
    fi

    if ! command -v parallel &>/dev/null; then
        log_warn "GNU Parallel not found — using bash background-job engine."
        log_warn "For best performance: sudo apt-get install parallel"
    fi

    if ! command -v flock &>/dev/null; then
        log_warn "flock not found — file writes may interleave under high concurrency."
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  INPUT SANITISATION
# ══════════════════════════════════════════════════════════════════════════════

# Returns a cleaned subdomain string, or empty string for lines to skip.
clean_line() {
    local line="$1"
    # Strip BOM, CR, leading/trailing whitespace
    line="${line//$'\xef\xbb\xbf'/}"
    line="${line//$'\r'/}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    # Skip comment lines and empty lines
    [[ -z "$line" || "$line" == \#* ]] && echo "" && return
    # Basic subdomain sanity — allow alphanumeric, hyphen, dot, wildcard prefix
    if ! [[ "$line" =~ ^(\*\.)?[a-zA-Z0-9][a-zA-Z0-9.\-]*\.[a-zA-Z]{2,}$ ]]; then
        log_verbose "Skipping invalid subdomain: '$line'"
        echo ""; return
    fi
    echo "$line"
}

# ══════════════════════════════════════════════════════════════════════════════
#  WILDCARD DETECTION
# ══════════════════════════════════════════════════════════════════════════════

# Check if a domain has wildcard DNS (resolves random subdomains).
# Returns 0 if wildcard detected, 1 otherwise.
is_wildcard_domain() {
    local domain="$1"
    local rand_sub
    rand_sub="sub2ip-wc-$(tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c12).${domain}"
    local result
    result=$(query_single "$rand_sub" "$DNS_TOOL" 2>/dev/null || true)
    [[ -n "$result" ]]
}

wildcard_check_domains() {
    local -A checked=()
    local -A warned=()
    while IFS= read -r raw; do
        local sub
        sub=$(clean_line "$raw")
        [[ -z "$sub" ]] && continue
        # Extract apex domain (last two labels)
        local apex
        apex=$(echo "$sub" | awk -F'.' '{if(NF>=2) print $(NF-1)"."$NF; else print $0}')
        if [[ -z "${checked[$apex]:-}" ]]; then
            checked[$apex]=1
            if is_wildcard_domain "$apex"; then
                warned[$apex]=1
                log_warn "Wildcard DNS detected on ${BOLD}${apex}${NC} — results may include false positives."
            fi
        fi
    done < "$INPUT_FILE"
}

# ══════════════════════════════════════════════════════════════════════════════
#  DNS QUERY ENGINE
# ══════════════════════════════════════════════════════════════════════════════

# Low-level single query — returns raw tool output
query_single() {
    local subdomain="$1"
    local tool="$2"

    case "$tool" in
        dig)
            local args=()
            [[ -n "$RESOLVER" ]] && args+=("@${RESOLVER}")
            args+=("$subdomain" "$RECORD_TYPE" "+short" "+time=${TIMEOUT}" "+tries=1")
            dig "${args[@]}" 2>/dev/null
            ;;
        host)
            local args=("-t" "$RECORD_TYPE" "-W" "$TIMEOUT")
            args+=("$subdomain")
            [[ -n "$RESOLVER" ]] && args+=("$RESOLVER")
            host "${args[@]}" 2>/dev/null
            ;;
    esac
}

# Query with retries and exponential backoff
query_dns() {
    local subdomain="$1"
    local tool="$2"
    local attempt=0
    local output=""

    while (( attempt <= RETRIES )); do
        output=$(query_single "$subdomain" "$tool")
        if [[ -n "$output" ]]; then
            echo "$output"
            return 0
        fi
        (( attempt++ ))
        if (( attempt <= RETRIES )); then
            local delay=$(( attempt * attempt ))   # 1s, 4s backoff
            log_verbose "Retry $attempt/$RETRIES for $subdomain (backoff ${delay}s)"
            sleep "$delay"
        fi
    done
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  RESULT FILTERING — per tool, per record type
# ══════════════════════════════════════════════════════════════════════════════

filter_results() {
    local output="$1"
    local type="$2"
    local tool="$3"

    case "$tool" in
        # ── dig: +short already strips most garbage ────────────────────────────
        dig)
            case "$type" in
                A|AAAA)
                    # Exclude CNAME hops (lines without digits at start) when type=A/AAAA
                    echo "$output" | grep -Eo '([0-9a-fA-F:.]+)' | grep -v '^\.'
                    ;;
                CNAME)
                    echo "$output" | sed 's/\.$//' | grep -v '^$'
                    ;;
                MX)
                    # Strip priority prefix (e.g., "10 mail.example.com.")
                    echo "$output" | awk '{print $NF}' | sed 's/\.$//'
                    ;;
                NS)
                    echo "$output" | sed 's/\.$//' | grep -v '^$'
                    ;;
                TXT)
                    echo "$output" | sed 's/^"//;s/"$//' | grep -v '^$'
                    ;;
                SOA)
                    echo "$output" | grep -v '^$'
                    ;;
                ANY)
                    echo "$output" | grep -v '^$'
                    ;;
            esac
            ;;

        # ── host: verbose output needs parsing ────────────────────────────────
        host)
            case "$type" in
                A)
                    echo "$output" | grep ' has address '       | awk '{print $NF}'
                    ;;
                AAAA)
                    echo "$output" | grep ' has IPv6 address '  | awk '{print $NF}'
                    ;;
                CNAME)
                    echo "$output" | grep ' is an alias for '   | awk '{print $NF}' | sed 's/\.$//'
                    ;;
                MX)
                    echo "$output" | grep ' mail is handled by '| awk '{print $NF}' | sed 's/\.$//'
                    ;;
                NS)
                    echo "$output" | grep ' name server '       | awk '{print $NF}' | sed 's/\.$//'
                    ;;
                TXT)
                    echo "$output" | grep ' descriptive text '  | cut -d'"' -f2
                    ;;
                SOA)
                    echo "$output" | grep 'SOA\|start of authority'
                    ;;
                ANY)
                    echo "$output" | grep -v '^$'
                    ;;
            esac
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  ATOMIC WRITE & STATISTICS
# ══════════════════════════════════════════════════════════════════════════════

# Atomic counter increment using a file (portable, no bash4 associative lock needed)
increment_stat() {
    local stat_file="$1"
    # Use flock if available for true atomicity, otherwise append a token
    if command -v flock &>/dev/null; then
        ( flock -x 9; echo "1" >> "$stat_file" ) 9>"${stat_file}.lock"
    else
        echo "1" >> "$stat_file"
    fi
}

count_stat() { wc -l < "$1" 2>/dev/null || echo 0; }

# Write a resolved result — atomic via flock when available
write_result() {
    local line="$1"           # clean line to write (no ANSI)

    if [[ -n "$OUTPUT_FILE" ]]; then
        if command -v flock &>/dev/null; then
            ( flock -x 9; echo "$line" >> "$OUTPUT_FILE" ) 9>"$LOCK_FILE"
        else
            # flock unavailable — sequential bash I/O is still atomic per write(2)
            echo "$line" >> "$OUTPUT_FILE"
        fi
    else
        # stdout: colour is fine
        echo -e "$line"
    fi
}

# Format a single result line according to --format
format_result() {
    local subdomain="$1"
    local value="$2"

    case "$FORMAT" in
        plain)
            # For file: no colour; for stdout: colour is added by caller
            echo "${subdomain}|${value}"
            ;;
        csv)
            # Escape commas inside TXT/SOA values
            local safe_value="${value//\"/\"\"}"
            echo "\"${subdomain}\",\"${safe_value}\""
            ;;
        json)
            # Minimal JSON object per line (JSON-Lines)
            local ts
            ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
            printf '{"subdomain":"%s","type":"%s","value":"%s","ts":"%s"}\n' \
                "$subdomain" "$RECORD_TYPE" "${value//\"/\\\"}" "$ts"
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  CORE WORKER
# ══════════════════════════════════════════════════════════════════════════════

process_subdomain() {
    local raw_subdomain="$1"

    # Sanitise
    local subdomain
    subdomain=$(clean_line "$raw_subdomain")
    if [[ -z "$subdomain" ]]; then
        increment_stat "$STAT_SKIPPED"
        return 0
    fi

    log_verbose "Querying $subdomain [$RECORD_TYPE]"

    # Rate limiting
    if (( RATE_LIMIT > 0 )); then
        local sleep_sec
        sleep_sec=$(awk "BEGIN{printf \"%.3f\", $RATE_LIMIT/1000}")
        sleep "$sleep_sec"
    fi

    # DNS query with retries
    local raw_output
    if ! raw_output=$(query_dns "$subdomain" "$DNS_TOOL"); then
        log_verbose "All retries failed: $subdomain"
        increment_stat "$STAT_FAILED"
        return 0
    fi

    # Filter by record type
    local filtered
    filtered=$(filter_results "$raw_output" "$RECORD_TYPE" "$DNS_TOOL")

    if [[ -z "$filtered" ]]; then
        log_verbose "No $RECORD_TYPE records: $subdomain"
        increment_stat "$STAT_FAILED"
        return 0
    fi

    # Deduplicate multi-line answers (e.g. multiple A records)
    local -A seen_values=()
    local any_written=0

    while IFS= read -r value; do
        [[ -z "$value" ]] && continue
        [[ -n "${seen_values[$value]:-}" ]] && continue
        seen_values[$value]=1

        local formatted_line
        formatted_line=$(format_result "$subdomain" "$value")

        if [[ -n "$OUTPUT_FILE" ]]; then
            write_result "$formatted_line"
        else
            # Colour only for stdout
            case "$FORMAT" in
                plain) echo -e "${GREEN}${subdomain}${NC} -> ${CYAN}${value}${NC}" ;;
                *)     echo "$formatted_line" ;;
            esac
        fi
        any_written=1
    done <<< "$filtered"

    if (( any_written )); then
        increment_stat "$STAT_RESOLVED"
    else
        increment_stat "$STAT_FAILED"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  CONCURRENCY ENGINE
# ══════════════════════════════════════════════════════════════════════════════

# fd-based semaphore: open THREADS tokens in a named pipe, workers consume/release
run_with_semaphore() {
    local fifo="${TMP_DIR}/sem_fifo"
    mkfifo "$fifo"
    # Open the FIFO for reading AND writing on fd 3 (keeps it open)
    exec 3<>"$fifo"

    # Seed the semaphore with THREADS tokens
    local i
    for (( i=0; i<THREADS; i++ )); do printf '.' >&3; done

    local total=0
    local resolved_display=0

    while IFS= read -r raw || [[ -n "$raw" ]]; do
        # Acquire a token (blocks when all threads busy)
        read -r -n1 -u3 _token

        (
            process_subdomain "$raw"
            printf '.' >&3    # Release token
        ) &

        (( ++total ))
    done < "$INPUT_FILE"

    # Drain — wait for all running workers to finish
    wait

    exec 3>&-           # Close semaphore fd
    rm -f "$fifo"
}

run_with_parallel() {
    export -f process_subdomain query_dns query_single filter_results \
               clean_line write_result format_result increment_stat log_verbose
    export RECORD_TYPE RESOLVER VERBOSE TIMEOUT RETRIES RATE_LIMIT FORMAT
    export OUTPUT_FILE DNS_TOOL LOCK_FILE
    export STAT_RESOLVED STAT_FAILED STAT_SKIPPED

    parallel --will-cite -j "$THREADS" process_subdomain {} < "$INPUT_FILE"
}

# ══════════════════════════════════════════════════════════════════════════════
#  OUTPUT FILE HEADER / FOOTER
# ══════════════════════════════════════════════════════════════════════════════

write_file_header() {
    [[ -z "$OUTPUT_FILE" ]] && return
    local ts
    ts=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
    case "$FORMAT" in
        plain)
            {
                echo "# sub2ip v3.0 — generated $ts"
                echo "# Input: $INPUT_FILE | Type: $RECORD_TYPE | Resolver: ${RESOLVER:-system}"
                echo "# Format: subdomain|value"
            } >> "$OUTPUT_FILE"
            ;;
        csv)
            echo '"subdomain","value"' >> "$OUTPUT_FILE"
            ;;
        json)
            : # JSON-Lines needs no header
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

print_summary() {
    local resolved failed skipped total elapsed
    resolved=$(count_stat "$STAT_RESOLVED")
    failed=$(count_stat "$STAT_FAILED")
    skipped=$(count_stat "$STAT_SKIPPED")
    total=$(( resolved + failed + skipped ))
    elapsed=$(( SECONDS - START_TIME ))

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD} Resolution Summary${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  %-20s %s\n" "Total processed:"  "${total}"
    printf "  %-20s ${GREEN}%s${NC}\n" "Resolved:"         "${resolved}"
    printf "  %-20s ${RED}%s${NC}\n"   "Failed/NXDOMAIN:"  "${failed}"
    printf "  %-20s ${DIM}%s${NC}\n"   "Skipped (invalid):" "${skipped}"
    printf "  %-20s %s\n" "Elapsed:"           "${elapsed}s"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [[ -n "$OUTPUT_FILE" && -f "$OUTPUT_FILE" ]]; then
        echo -e "${GREEN}[✓]${NC} Results written to: ${BOLD}${OUTPUT_FILE}${NC}"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
    START_TIME=$SECONDS

    parse_args "$@"
    init_tmp
    validate_input
    validate_resolver
    validate_tools

    # Prepare output file
    if [[ -n "$OUTPUT_FILE" ]]; then
        if ! touch "$OUTPUT_FILE" 2>/dev/null; then
            log_error "Cannot write to output file: $OUTPUT_FILE"; exit 1
        fi
        : > "$OUTPUT_FILE"          # Truncate cleanly
        write_file_header
    fi

    # Banner
    echo -e ""
    echo -e "${BOLD}${GREEN}sub2ip v3.0${NC} — Resolution Engine"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Input file  : $INPUT_FILE  ($(wc -l < "$INPUT_FILE") lines)"
    log_info "DNS tool    : $DNS_TOOL"
    log_info "Record type : $RECORD_TYPE"
    log_info "Threads     : $THREADS"
    log_info "Timeout     : ${TIMEOUT}s  |  Retries: $RETRIES"
    log_info "Format      : $FORMAT"
    [[ -n "$RESOLVER"    ]] && log_info "Resolver    : $RESOLVER"
    [[ -n "$OUTPUT_FILE" ]] && log_info "Output file : $OUTPUT_FILE"
    [[ $RATE_LIMIT -gt 0 ]] && log_info "Rate limit  : ${RATE_LIMIT}ms/query/thread"
    echo ""

    # Optional wildcard pre-check
    if (( WILDCARD_CHECK )); then
        log_info "Running wildcard DNS pre-check…"
        wildcard_check_domains
    fi

    # Run
    if command -v parallel &>/dev/null; then
        log_info "Engine: GNU Parallel"
        run_with_parallel
    else
        log_info "Engine: bash semaphore (fd-based, ${THREADS} slots)"
        run_with_semaphore
    fi

    print_summary
}

main "$@"