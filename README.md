## sub2ip

<p align="center">
<img width="1024" height="400" alt="image" src="https://github.com/user-attachments/assets/e149af0a-6811-425f-9906-803fc704ccdd" />
</p>

> [!NOTE]
> **sub2ip** is an ultra-advanced, production-grade Bash-based resolution engine designed to convert a list of subdomains into their corresponding DNS records — with full multi-threading, atomic output, retry logic, wildcard detection, and machine-readable output formats.

> [!CAUTION]
> **Use sub2ip only on assets you own or have explicit permission to test. Unauthorized DNS resolution or subsequent scanning can be illegal. The authors and project accept no responsibility for misuse of this tool.**

---

### What's New in v3.0

| Category | Change |
| :--- | :--- |
| 🐛 **14 bug fixes** | Including undefined `write_result()`, broken concurrency, ANSI-polluted files, dead code branches — see [CHANGELOG.md](CHANGELOG.md) |
| ⚡ **True semaphore engine** | fd-based token semaphore replaces the broken batch-gate; real N-way parallelism with no idle gaps |
| 🔁 **Retry with backoff** | `--retries N` with exponential backoff (1s, 4s…) on transient DNS failures |
| ⏱️ **Per-query timeout** | `--timeout SECS` enforced at the `dig`/`host` call level |
| 🌊 **Rate limiting** | `--rate-limit MS` delay per thread to respect DNS server load |
| 📄 **Output formats** | `--format plain|csv|json` — JSON-Lines output for SIEM/pipeline ingestion |
| 🌐 **Wildcard detection** | Pre-scan apex domains for wildcard DNS before resolution begins |
| 🧹 **Input sanitisation** | Strips BOM, CR, comments, whitespace; validates hostname syntax |
| 📊 **Completion summary** | Resolved / Failed / Skipped counts + elapsed time printed on exit |
| 🔢 **64 threads** | Thread cap raised from 16 → 64 |
| 🌍 **IPv6 resolver support** | `-s` now accepts IPv4, IPv6, or FQDN resolver addresses |

---

### Features

* **True Parallel Engine:** fd-based semaphore gives real `N`-way concurrency — up to **64 threads** — with GNU Parallel or native bash background jobs.
* **DNS Record Filtering:** Query A, AAAA, CNAME, MX, NS, TXT, SOA, and ANY records with clean per-type output parsing.
* **Custom DNS Resolvers:** IPv4, IPv6, or FQDN resolvers (e.g. `8.8.8.8`, `2001:4860::8888`, `resolver.example.com`).
* **Retry with Exponential Backoff:** Transient failures are retried automatically (`--retries`, default: 2).
* **Per-Query Timeout:** Hard deadline enforced at the `dig`/`host` system call (`--timeout`, default: 5s).
* **Rate Limiting:** Configurable inter-query delay per thread (`--rate-limit MS`) to avoid hammering resolvers.
* **Wildcard DNS Detection:** Probes apex domains before scanning and warns when results may be unreliable.
* **Machine-Readable Output:** `plain`, `csv`, and `json` (JSON-Lines) output formats.
* **Atomic File Writes:** `flock`-protected output prevents line interleaving under high concurrency.
* **Input Sanitisation:** Strips BOM, CRLF, comments (`#`), blank lines, and rejects invalid hostnames.
* **Completion Summary:** Resolved / Failed / Skipped totals and elapsed time on every run.
* **Verbose & No-Color Modes:** `-v` for debug output; `--no-color` for CI/log capture.
* **Comprehensive Help:** Built-in `--help` with colour-coded usage and examples.

---

### Installation

#### Option 1: Global Installation (Recommended)

```bash
git clone https://github.com/muhammadtaharana/sub2ip
cd sub2ip
sudo ./install.sh
```

The `install.sh` script will:
- Verify dependencies (`dig` or `host`; optional `parallel`, `flock`)
- Copy `sub2ip.sh` to `/usr/local/bin/sub2ip`
- Set appropriate permissions
- Enable global access from any directory

After installation, use from anywhere:
```bash
sub2ip subdomains.txt -o results.txt
```

#### Option 2: Local Usage

```bash
git clone https://github.com/muhammadtaharana/sub2ip
cd sub2ip
chmod +x sub2ip.sh
./sub2ip.sh subdomains.txt
```

#### Uninstall

```bash
sudo ./install.sh --uninstall
```

#### Dependencies

| Dependency | Role | Install |
| :--- | :--- | :--- |
| `dig` *(preferred)* | DNS lookups | `sudo apt-get install dnsutils` |
| `host` *(fallback)* | DNS lookups | `sudo apt-get install dnsutils` |
| `parallel` *(optional)* | GNU Parallel engine | `sudo apt-get install parallel` |
| `flock` *(optional)* | Atomic file writes | included in `util-linux` |

> [!TIP]
> Install all optional dependencies for maximum performance:
> ```bash
> sudo apt-get install dnsutils parallel util-linux
> ```

---

### Execution Workflow

| Phase | Description |
| :--- | :--- |
| **I: Initialization** | Parse args → validate input file, resolver, tools → init tmp directory |
| **II: Wildcard Pre-Check** | Probe each apex domain with a random subdomain to detect wildcard zones |
| **III: Parallel Dispatch** | Distribute subdomains across threads via fd-semaphore (bash) or GNU Parallel |
| **IV: DNS Query + Retry** | Each worker queries with timeout; retries on failure with exponential backoff |
| **V: Filter + Deduplicate** | Record-type-specific parsing; duplicate values per subdomain eliminated |
| **VI: Atomic Write** | Results written to stdout or file under `flock` lock |
| **VII: Summary** | Resolved / Failed / Skipped totals + elapsed time printed |

**v3.0 Performance:** 10,000 subdomains with 20 threads completes in ~60–90 seconds using `dig` and GNU Parallel.

---

### Usage

```
sub2ip <input_file> [OPTIONS]
```

#### Resolution Options

| Flag | Description | Default |
| :--- | :--- | :--- |
| `-r, --record TYPE` | DNS record type: `A AAAA CNAME MX NS TXT SOA ANY` | `A` |
| `-s, --server SERVER` | Custom resolver (IPv4 / IPv6 / FQDN) | system resolver |
| `--timeout SECS` | Per-query hard timeout | `5` |
| `--retries N` | Retry failed queries N times (exp. backoff) | `2` |
| `--no-wildcard` | Skip wildcard DNS pre-check | *(check enabled)* |

#### Performance Options

| Flag | Description | Default |
| :--- | :--- | :--- |
| `-t, --threads NUM` | Parallel threads (1–64) | `10` |
| `--rate-limit MS` | Delay (ms) between queries per thread | `0` |

#### Output Options

| Flag | Description | Default |
| :--- | :--- | :--- |
| `-o, --output FILE` | Write results to file | stdout |
| `-f, --format FORMAT` | `plain` / `csv` / `json` | `plain` |
| `-v, --verbose` | Enable debug output | off |
| `--no-color` | Disable ANSI colour codes | off |

---

### Usage Examples

#### Basic Usage

```bash
# Display help
sub2ip --help

# Resolve A records to screen
sub2ip subdomains.txt

# Save results to file
sub2ip subdomains.txt -o resolved_ips.txt
```

#### Multi-Threading

```bash
# 20 threads for large lists
sub2ip subdomains.txt -t 20 -o results.txt

# Maximum throughput (64 threads)
sub2ip massive_list.txt -t 64 -o ips.txt
```

#### DNS Record Types

```bash
# IPv4 (A records) — default
sub2ip domains.txt -r A -o ipv4.txt

# IPv6 (AAAA records)
sub2ip domains.txt -r AAAA -o ipv6.txt

# CNAME aliases
sub2ip domains.txt -r CNAME -o cnames.txt

# Mail servers
sub2ip domains.txt -r MX -o mail_servers.txt

# Nameservers
sub2ip domains.txt -r NS -o nameservers.txt

# TXT records
sub2ip domains.txt -r TXT -o txt_records.txt

# All records
sub2ip domains.txt -r ANY -o all_records.txt
```

#### Custom DNS Resolvers

```bash
# Google DNS (IPv4)
sub2ip subdomains.txt -s 8.8.8.8 -o results.txt

# Cloudflare DNS (IPv4)
sub2ip subdomains.txt -s 1.1.1.1 -o results.txt

# Google DNS (IPv6)  ← new in v3.0
sub2ip subdomains.txt -s 2001:4860:4860::8888 -o results.txt

# FQDN resolver  ← new in v3.0
sub2ip subdomains.txt -s resolver.example.com -o results.txt
```

#### Retry & Timeout Control *(new in v3.0)*

```bash
# 3 retries, 10s timeout per query
sub2ip subdomains.txt --retries 3 --timeout 10 -o results.txt

# Strict: no retries, 2s timeout
sub2ip subdomains.txt --retries 0 --timeout 2 -o fast.txt
```

#### Output Formats *(new in v3.0)*

```bash
# CSV output (header + quoted fields)
sub2ip domains.txt -f csv -o records.csv

# JSON-Lines output (one object per resolved value)
sub2ip domains.txt -f json -o records.jsonl

# Pipe JSON into jq
sub2ip domains.txt -f json | jq '.value'
```

#### Rate Limiting *(new in v3.0)*

```bash
# 200ms between queries per thread (respectful scanning)
sub2ip domains.txt -t 8 --rate-limit 200 -o results.txt
```

#### Advanced / Pipeline Examples

```bash
# Full-featured: 20 threads, CNAME, Cloudflare DNS, retries, JSON output
sub2ip domains.txt -t 20 -r CNAME -s 1.1.1.1 --retries 3 -f json -o cnames.jsonl

# Skip wildcard check for speed on trusted input
sub2ip domains.txt --no-wildcard -t 30 -o results.txt

# Suppress colour for CI logs
sub2ip domains.txt --no-color -o results.txt 2>&1 | tee scan.log

# Chain with subfinder → sub2ip → httpx
subfinder -d example.com | sort -u > subdomains.txt
sub2ip subdomains.txt -t 20 -s 8.8.8.8 -o resolved_ips.txt
httpx -l resolved_ips.txt -o http_results.txt

# Pipe directly from subfinder
subfinder -d example.com | sort -u | sub2ip /dev/stdin -t 16 -o final_ips.txt
```

---

### Output Structure

#### Console Output (plain, stdout)

```text
[*] Input file  : subdomains.txt  (500 lines)
[*] DNS tool    : dig
[*] Record type : A
[*] Threads     : 10
[!] Wildcard DNS detected on example.com — results may include false positives.

example.com          -> 93.184.216.34
sub.example.com      -> 93.184.216.35
api.example.com      -> 93.184.216.36

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Resolution Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total processed:     500
  Resolved:            412
  Failed/NXDOMAIN:     81
  Skipped (invalid):   7
  Elapsed:             43s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### File Output — plain

```text
# sub2ip v3.0 — generated 2026-05-07 09:00:00 UTC
# Input: subdomains.txt | Type: A | Resolver: 8.8.8.8
# Format: subdomain|value
example.com|93.184.216.34
sub.example.com|93.184.216.35
api.example.com|93.184.216.36
```

#### File Output — csv (`-f csv`)

```csv
"subdomain","value"
"example.com","93.184.216.34"
"sub.example.com","93.184.216.35"
"api.example.com","93.184.216.36"
```

#### File Output — json (`-f json`)

```jsonl
{"subdomain":"example.com","type":"A","value":"93.184.216.34","ts":"2026-05-07T09:00:00Z"}
{"subdomain":"sub.example.com","type":"A","value":"93.184.216.35","ts":"2026-05-07T09:00:01Z"}
{"subdomain":"api.example.com","type":"A","value":"93.184.216.36","ts":"2026-05-07T09:00:01Z"}
```

#### Verbose Output (`-v`)

```text
[DBG] Querying example.com [A]
[DBG] Querying sub.example.com [A]
[DBG] Retry 1/2 for flaky.example.com (backoff 1s)
[DBG] Querying api.example.com [A]
[DBG] No A records: nxdomain.example.com
```

---

### TO-DO

- [x] Multi-threading with GNU Parallel / bash background jobs
  - ✓ True fd-based semaphore (v3.0) — up to 64 threads
  - ✓ ~10× faster for large lists vs v1.0

- [x] DNS record type filtering (A, AAAA, CNAME, MX, NS, TXT, SOA, ANY)
  - ✓ Clean per-type parsing for both `dig` and `host`
  - ✓ Result deduplication per subdomain

- [x] Custom DNS resolver support
  - ✓ IPv4, IPv6, and FQDN resolver addresses (v3.0)
  - ✓ Tested with Google, Cloudflare, Quad9

- [x] Output format options — JSON, CSV *(v3.0)*
  - ✓ `plain`, `csv`, `json` (JSON-Lines) via `--format`

- [x] Rate limiting to respect DNS server load *(v3.0)*
  - ✓ `--rate-limit MS` per thread

- [x] Retry logic on transient failures *(v3.0)*
  - ✓ `--retries N` with exponential backoff

- [x] Wildcard DNS detection *(v3.0)*
  - ✓ Pre-scan probe per apex domain; warn on wildcard zones

### Future Enhancements

- [ ] Real-time progress bar for large batches
- [ ] Query result caching to skip duplicate apex lookups
- [ ] Distributed processing across multiple machines
- [ ] Integration wrappers for subfinder, gau, assetfinder
- [ ] Batch HTTP/ping verification on resolved IPs
- [ ] XML output format
- [ ] Config file support (`~/.sub2iprc`)