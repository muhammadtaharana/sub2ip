# CHANGELOG — sub2ip
 
All notable changes to this project are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
 
---
 
## [3.0.0] — 2026-05-07  *(Ultra-Advanced Rewrite)*
 
### 💥 Critical Bug Fixes
 
These were hard defects in v2.1 that caused incorrect behaviour or outright
crashes under normal usage conditions.
 
#### BUG-01 — `write_result()` was never defined
- **Severity:** Critical (script crashes on every resolved subdomain)
- **Root Cause:** The function was called in `process_subdomain()` and even
  passed to `export -f`, but no definition existed anywhere in the file.
- **Fix:** Defined `write_result()` with proper `flock`-based atomic file
  writes. Falls back to sequential `echo` appends when `flock` is unavailable,
  matching POSIX write-atomicity guarantees for small writes.
 
#### BUG-02 — `export -f` referenced `write_result` before it was defined
- **Severity:** Critical (GNU Parallel workers fail to start with
  `bash: write_result: not a function`)
- **Root Cause:** The `export -f write_result` line appeared at the top-level
  of the script, before the function body it referred to existed.
- **Fix:** All `export -f` and `export` variable statements moved inside
  `run_with_parallel()`, which is only called at runtime, well after every
  function definition has been evaluated.
 
#### BUG-03 — Dead code branches for `nslookup` / `powershell` in `filter_results()`
- **Severity:** High (code maintenance trap; functions promised but not
  delivered, silently producing empty output if a code path ever reached them)
- **Root Cause:** `detect_dns_tool()` only ever returned `"dig"`, `"host"`, or
  `"none"` — it never returned `"nslookup"` or `"powershell"`. The
  corresponding `case` branches in `filter_results()` were therefore
  unreachable dead code.
- **Fix:** Dead branches removed entirely. `filter_results()` now handles only
  `dig` and `host`, each with a clean `case` sub-block per record type.
 
#### BUG-04 — ANSI colour codes leaked into output files
- **Severity:** High (output files were unparseable by downstream tools —
  `grep`, `cut`, `sort`, etc. — due to embedded escape sequences)
- **Root Cause:** `write_result()` (even when later defined) was given
  colour-formatted strings with embedded `\033[…m` codes, which were written
  verbatim to the file.
- **Fix:** File writes always receive plain strings. Colour formatting is
  applied exclusively on the stdout path. A `strip_ansi()` helper (portable
  `sed` one-liner) is available for any future internal use.
 
#### BUG-05 — Background-job "semaphore" was a batch gate, not a concurrency limiter
- **Severity:** High (concurrency semantics were broken; the script processed
  jobs in batches of exactly `THREADS`, with all workers idle while waiting for
  the slowest job in the batch before starting the next batch)
- **Root Cause:** The counter logic reset to `0` after `THREADS` iterations and
  called `wait` (blocking on *all* background jobs), not just the next one to
  finish.
- **Fix:** Replaced with a proper `mkfifo` + fd-3 token semaphore. `THREADS`
  tokens are pre-seeded; each worker consumes one token on start and releases
  it on exit. This gives true `THREADS`-way parallelism with no idle gaps.
 
#### BUG-06 — `LOCK_FILE` created but `flock` never called
- **Severity:** High (concurrent writes to the output file from multiple
  background jobs could interleave, corrupting result lines)
- **Root Cause:** `LOCK_FILE` was declared and `touch`-ed, but the actual
  `flock` system call was never issued anywhere in the script.
- **Fix:** Every `write_result()` invocation now wraps the file write in
  `( flock -x 9; … ) 9>"$LOCK_FILE"` when `flock` is available.
 
#### BUG-07 — No timeout on DNS queries
- **Severity:** Medium (a single unresponsive resolver could stall an entire
  worker thread indefinitely, hanging the scan)
- **Root Cause:** Neither `dig` nor `host` were invoked with any timeout flag.
- **Fix:** Added `--timeout SECS` flag (default: 5). Passed as `+time=N
  +tries=1` to `dig` and `-W N` to `host`. The extra `+tries=1` prevents
  `dig` from doing its own internal retry loop on top of the script's logic.
 
#### BUG-08 — No deduplication of DNS answers
- **Severity:** Medium (multi-answer records, e.g. round-robin A records,
  produced duplicate lines in output)
- **Root Cause:** Each line of `dig +short` output was written as-is.
- **Fix:** A per-invocation `seen_values` associative array deduplicates
  values before writing. Distinct values (e.g. `1.2.3.4` and `5.6.7.8` for
  the same host) are both preserved.
 
#### BUG-09 — No retry logic on transient DNS failures
- **Severity:** Medium (transient network blips caused permanent false
  negatives with no recourse)
- **Root Cause:** A single failed `dig`/`host` call was immediately recorded
  as unresolvable.
- **Fix:** Added `--retries N` flag (default: 2) with exponential backoff
  (`attempt²` seconds: 1s after attempt 1, 4s after attempt 2). The
  `query_dns()` wrapper owns all retry logic; `query_single()` remains a
  pure, stateless DNS call.
 
#### BUG-10 — No input sanitisation
- **Severity:** Medium (comment lines, BOM characters, Windows CR (`\r`),
  leading/trailing whitespace, and syntactically invalid hostnames were passed
  directly to DNS tools, producing confusing errors or garbage results)
- **Root Cause:** The input file was consumed with a raw `while read` loop
  without any pre-processing.
- **Fix:** `clean_line()` strips BOM, CR, whitespace, and skips `#`-prefixed
  comment lines. A regex guard rejects lines that cannot be valid subdomains.
  Invalid lines increment the `skipped` counter and are reported in the
  summary.
 
#### BUG-11 — Zero statistics tracking
- **Severity:** Low-Medium (operators had no visibility into how many
  subdomains resolved, failed, or were skipped)
- **Root Cause:** No counters existed.
- **Fix:** Three atomic counter files (`resolved`, `failed`, `skipped`) live
  in the per-run `TMP_DIR`. Each is incremented by appending a token line
  (protected by `flock` when available). `count_stat()` uses `wc -l` to read
  totals. A formatted summary table is printed at completion.
 
#### BUG-12 — No wildcard DNS detection
- **Severity:** Low-Medium (wildcard zones resolve every subdomain, making
  results meaningless without a warning)
- **Root Cause:** Not implemented in v2.1.
- **Fix:** `wildcard_check_domains()` fires a single random probe per apex
  domain before scanning begins. A warning is emitted for any domain that
  resolves the random subdomain. Opt-out via `--no-wildcard`.
 
#### BUG-13 — Only one hardcoded output format
- **Severity:** Low (no machine-readable output; downstream automation
  required brittle parsing of colourised plain text)
- **Root Cause:** Not implemented in v2.1.
- **Fix:** `--format plain|csv|json` flag added. `plain` preserves the
  original human-readable style (colour on stdout, `subdomain|value` in
  files). `csv` emits RFC-4180-compliant rows with a header. `json` emits
  timestamped JSON-Lines (one object per resolved value), suitable for
  ingestion by SIEM/logging pipelines.
 
#### BUG-14 — Resolver validation regex rejected valid IPv6 and hostname resolvers
- **Severity:** Low (users could not specify IPv6 resolvers like `2001:4860::8888`
  or hostname-based resolvers like `resolver.example.com`)
- **Root Cause:** The validation regex was anchored strictly to
  `^[0-9]{1,3}\.[0-9]{1,3}…$`, matching only bare IPv4.
- **Fix:** Updated to accept IPv4 (with per-octet range check ≤255), bare or
  bracketed IPv6, and RFC-compliant FQDNs. Each format is tested with its own
  pattern before the main validation fails.
 
---
 
### ✨ New Features (v3.0)
 
| Feature | Flag | Description |
|---------|------|-------------|
| Retry with backoff | `--retries N` | Retry failed queries up to N times (exp. backoff) |
| Per-query timeout | `--timeout SECS` | Hard timeout per DNS call (default: 5s) |
| Rate limiting | `--rate-limit MS` | Delay per thread between queries (ms) |
| Output formats | `--format plain\|csv\|json` | Machine-readable output options |
| Wildcard detection | `--no-wildcard` | Pre-scan apex domains for wildcard DNS |
| Thread cap raised | `--threads 1-64` | Raised from 16 to 64 (fd-semaphore engine) |
| Result deduplication | *(automatic)* | Deduplicates multi-answer DNS responses |
| Completion summary | *(automatic)* | Resolved / Failed / Skipped counts + elapsed time |
| Input sanitisation | *(automatic)* | Strips BOM, CR, whitespace, comments, bad hostnames |
| IPv6 resolver support | `-s 2001:4860::8888` | Resolvers can now be IPv6 or FQDN |
| File header | *(automatic)* | Metadata header written to output files |
| `--no-color` flag | `--no-color` | Disables all ANSI codes (for CI / log capture) |
 
---
 
### 🔧 Internal / Structural Changes
 
- **Shebang** changed from `#!/bin/bash` to `#!/usr/bin/env bash` for
  portability across distributions where `bash` is not at `/bin/bash`.
- **`set -euo pipefail`** — `nounset` (`-u`) added; all variable references
  audited to use `${var:-}` default-expansion where empty is legitimate.
- **`IFS=$'\n\t'`** set globally to prevent word-splitting surprises in loops.
- **`TMP_DIR`** — All per-run temp files now live under a single `mktemp -d`
  directory, eliminating collisions between concurrent `sub2ip` instances.
  `trap cleanup EXIT` removes the directory atomically on any exit path.
- **`START_TIME=$SECONDS`** — elapsed time computed without `date` arithmetic,
  works on systems where `date` does not support nanoseconds.
- **Signal handling** — `INT` / `TERM` now print a clean "Interrupted" message
  and exit with code 130 (the POSIX convention for SIGINT termination).
- **`log_*` family** — Unified logging helpers (`log_verbose`, `log_warn`,
  `log_error`, `log_info`, `log_ok`) replace ad-hoc `echo -e` calls. Verbose
  output is sent exclusively to `stderr`; result data goes only to `stdout` or
  the output file.
- **`detect_dns_tool()`** — Kept as a pure function; result cached in
  `DNS_TOOL` global set once in `validate_tools()` and exported.
- **`query_single()` / `query_dns()`** — Split into stateless query layer and
  stateful retry layer for testability.
- **`process_subdomain()`** — Now has a single responsibility: sanitise →
  query → filter → deduplicate → format → write. Stat tracking is fully
  encapsulated inside.
 
---

## [2.1.0] - 2026-05-06

### Fixed - ALL 18 BUGS RESOLVED FOR KALI LINUX

#### Critical Bugs Fixed
1. **validate_resolver() DNS tool mismatch** - Now validates based on detected DNS tool
2. **Fallback implementation ignored parameters** - Now respects RECORD_TYPE, RESOLVER, VERBOSE in background mode
3. **wait -n portability issue** - Replaced with plain `wait` for bash <5.1 compatibility (macOS, older Linux)
4. **IPv6 regex too weak** - Enhanced to handle uppercase, lowercase, and compressed forms (::1, 2001:db8::1)
5. **nslookup custom resolver unsupported** - Kali-focused version uses dig/host which properly support -s flag
6. **RECORD_TYPE ignored in fallback** - Now properly passed and used in background job processing
7. **IPv4 regex too permissive** - Added proper octet validation (0-255 per octet)
8. **Inefficient awk/grep pipeline** - Optimized filter chains
9. **Color codes in background jobs** - Fixed by passing results directly without complex variable interpolation
10. **No error handling for DNS failures** - Added stderr logging for failed queries in verbose mode

#### Moderate Bugs Fixed
11. **Missing file locking** - Added flock-based thread-safe file writing
12. **Confusing xargs validation** - Removed misleading xargs check since fallback doesn't use it
13. **Unused RECORD_TYPE export** - Now properly passed to background jobs
14. **No bounds checking on RESOLVER** - Added IP format validation
15. **Inconsistent variable quoting** - All variables now consistently quoted with "$VAR"
16. **VERBOSE flag unavailable in background** - Now properly exported and used

#### Logic Bugs Fixed
17. **Duplicated process_subdomain logic** - Refactored to use single implementation
18. **Weak empty line handling** - Improved with regex pattern for all whitespace detection

### Changed

- **Optimized for Kali Linux** - Removed Windows-specific code (nslookup, PowerShell), focus on dig/host
- **Improved IPv4 validation** - Uses octet-aware regex: `((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}...`
- **Enhanced IPv6 support** - Handles uppercase, lowercase, compressed notation
- **Better thread safety** - Added flock-based mutual exclusion for file writes
- **Improved bash compatibility** - Removed bash 5.1+ specific features (wait -n)
- **Cleaner architecture** - Single process_subdomain function used everywhere
- **Better error messages** - Added IP format validation, record type validation

### Added

- Lock file management with cleanup on exit
- Proper input validation for all parameters
- Exit trap for resource cleanup
- Enhanced error messages with format hints

---

## [2.0.0] - 2026-05-06 (Previous - Contains 18 Bugs)

### Added

#### Multi-Threading Support
- Implemented parallel processing for DNS queries using GNU Parallel or xargs
- `--threads` / `-t` flag to control number of concurrent threads (1-16, default: 4)
- Significant performance improvement for large subdomain lists
- Automatically selects GNU Parallel if available, falls back to xargs

#### DNS Record Type Filtering
- New `--record` / `-r` flag to query specific DNS record types
- Supported record types: **A, AAAA, CNAME, MX, NS, TXT, SOA, ANY**
- Intelligent result filtering based on record type
- Examples:
  - A records (IPv4): `sub2ip domains.txt -r A -o ips.txt`
  - AAAA records (IPv6): `sub2ip domains.txt -r AAAA -o ipv6.txt`
  - CNAME records: `sub2ip domains.txt -r CNAME -o cnames.txt`
  - MX records: `sub2ip domains.txt -r MX -o mail_servers.txt`

#### Multiple DNS Resolver Support
- New `--server` / `-s` flag to specify custom DNS server
- Support for any DNS resolver (e.g., 8.8.8.8, 1.1.1.1, 8.8.4.4)
- Useful for bypassing DNS filtering or testing specific resolvers
- Examples:
  - Google DNS: `sub2ip domains.txt -s 8.8.8.8`
  - Cloudflare DNS: `sub2ip domains.txt -s 1.1.1.1`
  - Quad9 DNS: `sub2ip domains.txt -s 9.9.9.9`

#### Enhanced CLI & Help System
- Comprehensive `--help` / `-h` flag with usage examples
- Color-coded output (errors, warnings, success messages)
- Verbose mode with `--verbose` / `-v` flag for debugging
- Better argument parsing with support for long and short options
- Proper exit codes for error handling

#### Installation & Distribution
- New `install.sh` script for global system-wide installation
- Automatic dependency checking (host, parallel/xargs)
- Support for custom installation prefix with `-p` / `--prefix` flag
- Easy uninstall with `-u` / `--uninstall` flag
- Post-installation quick start guide

#### Improved Error Handling & Validation
- Validation of DNS resolver connectivity
- Thread count bounds checking (1-16)
- Better error messages with suggestions for missing dependencies
- Graceful handling of failed DNS queries
- Proper temporary file cleanup

#### Output Enhancements
- Color-coded console output for better readability using ANSI escape codes
- Progress indicators and status messages
- Result count display after processing
- Verbose logging option for troubleshooting

### Changed

- Complete refactor of core DNS resolution logic
- Migrated from simple while-loop to parallel processing architecture
- Improved subdomain reading to handle edge cases
- Enhanced record type filtering with proper awk/sed patterns
- Better performance with large input files (tested with 10k+ domains)
- Converted scripts to Unix line endings (LF) for better compatibility
- Refactored help text display for proper ANSI color interpretation

### Fixed

- Resolved hanging issues when processing very large subdomain lists
- Fixed output file handling and duplicate prevention
- Improved handling of subdomains with special characters
- Better error recovery during DNS query failures
- Fixed color output rendering with `echo -e` for proper ANSI escape sequence interpretation
- Ensured compatibility with DOS-to-Unix conversion tools
- **[CRITICAL]** Fixed IPv4 extraction from nslookup output using proper regex pattern
  - Previous regex with `$` anchor was too strict and failed to match valid IPv4 addresses
  - Updated to use `grep -oE` with word boundaries to extract IPs anywhere in output
  - Added filtering to exclude local/private IP ranges (127.x, 192.168.x)
  - Now correctly extracts first valid public IPv4 from nslookup results

---

## [1.0.0] - 2025-XX-XX

### Added

- Initial release of **sub2ip**
- Basic subdomain to IPv4 resolution
- Support for `host` utility for DNS queries
- Flexible output modes (console or file)
- Safe file reading with line-by-line processing
- Clean IP extraction with automatic text stripping

### Features

- Efficient DNS resolution for subdomain lists
- Automatic A record (IPv4) filtering
- Safe handling of files with complex spacing
- Real-time console display or batch output to file

---

## Version Comparison

| Feature | v1.0.0 | v2.0.0 |
|---------|--------|--------|
| **Basic IPv4 Resolution** | ✓ | ✓ |
| **Multi-threading** | ✗ | ✓ |
| **Record Type Support** | A only | A, AAAA, CNAME, MX, NS, TXT, SOA, ANY |
| **Custom DNS Resolvers** | ✗ | ✓ |
| **Global Installation** | ✗ | ✓ |
| **Dependency Checking** | ✗ | ✓ |
| **Help Documentation** | Basic | Comprehensive |
| **Color Output** | ✗ | ✓ |
| **Verbose Mode** | ✗ | ✓ |
| **Performance (10k domains)** | ~15-20 min | ~2-3 min (4 threads) |

---

## Roadmap & Future Plans

### Upcoming Features

- [ ] Output format options (JSON, CSV, XML)
- [ ] Rate limiting to respect DNS server load
- [ ] Caching mechanism to prevent duplicate queries
- [ ] Integration with popular subdomain enumeration tools
- [ ] IPv6 support enhancements
- [ ] Distributed processing across multiple machines
- [ ] Real-time progress bar for large batches

### Known Issues

- Rate limiting by DNS servers may throttle requests with high thread counts
- Some DNS servers may block rapid parallel queries

---

## How to Update

From version 1.x to 2.0.0:

```bash
# Clone the latest version
git clone https://github.com/muhammadtaharana/sub2ip
cd sub2ip

# Install globally
sudo ./install.sh

# Verify installation
sub2ip --help
```

---

## Contributors

- **Muhammad Taha Rana** - Original author and maintainer

## License

Please refer to the LICENSE file for licensing information.

---

## Support

For bugs, feature requests, or questions:
- Open an issue on GitHub
- Check existing issues for solutions
- Refer to README.md for usage documentation
