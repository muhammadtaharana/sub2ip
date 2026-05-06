## sub2ip

<p align="center">
<img width="1024" height="500" alt="image" src="https://github.com/user-attachments/assets/e149af0a-6811-425f-9906-803fc704ccdd" />
</p>

> [!NOTE]
> **sub2ip** is a robust and efficient Bash-based resolution engine designed to convert a list of subdomains into their corresponding IPv4 addresses.

> [!CAUTION]
> **Use sub2ip only on assets you own or have explicit permission to test. Unauthorized DNS resolution or subsequent scanning can be illegal. The authors and project accept no responsibility for misuse of this tool.**

### Features

* **Multi-Threading Support:** Resolve vast lists of subdomains in parallel using GNU Parallel or xargs - up to **16 concurrent threads** for massive performance gains.
* **DNS Record Filtering:** Query multiple DNS record types including A, AAAA, CNAME, MX, NS, TXT, SOA, and ANY records.
* **Custom DNS Resolvers:** Specify alternative DNS servers (e.g., 8.8.8.8, 1.1.1.1) for flexibility and privacy.
* **Efficient Resolution:** Resolves vast lists of subdomains quickly using the standard `host` utility.
* **Clean IP Extraction:** Automatically strips unnecessary DNS information to output clean results.
* **Intelligent File Handling:** Safely processes input files using line-by-line reading to prevent issues with complex spacing.
* **Flexible Output:** Supports both real-time console display and direct logging to an output file.
* **Global Installation:** Install once, use from anywhere with the `install.sh` script.
* **Comprehensive Help:** Built-in help system with color-coded output and usage examples.
* **Verbose Mode:** Debug mode for troubleshooting DNS resolution issues.

### Installation

#### Option 1: Global Installation (Recommended)

Clone the repository and run the installation script:

```bash
git clone https://github.com/muhammadtaharana/sub2ip
cd sub2ip
sudo ./install.sh
```

The `install.sh` script will:
- Verify dependencies (`host`, `parallel`/`xargs`)
- Copy sub2ip to `/usr/local/bin/sub2ip`
- Set appropriate permissions
- Enable global access from any directory

After installation, use from anywhere:
```bash
sub2ip subdomains.txt -o results.txt
```

#### Option 2: Local Usage

For local usage without installation:

```bash
git clone https://github.com/muhammadtaharana/sub2ip
cd sub2ip
chmod +x sub2ip.sh
./sub2ip.sh subdomains.txt
```

#### Uninstall

To remove sub2ip from your system:

```bash
sudo ./install.sh --uninstall
```

#### Dependencies

The installation script will check for required dependencies:

- **host** - DNS lookup utility
  - Ubuntu/Debian: `sudo apt-get install dnsutils`
  - RHEL/CentOS: `sudo yum install bind-utils`
  - macOS: `brew install bind`

- **parallel** or **xargs** - For multi-threading
  - Ubuntu/Debian: `sudo apt-get install moreutils`
  - RHEL/CentOS: `sudo yum install moreutils`
  - macOS: `brew install moreutils`
### Execution Workflow

The resolution engine processes the input via the following parallel pipeline:

| Phase | Description |
| :--- | :--- |
| **I: Initialization** | Validates the input file, checks for optional parameters, and verifies dependencies |
| **II: Parallel Dispatch** | Distributes subdomains across multiple threads (default: 4, max: 16) using GNU Parallel or xargs |
| **III: DNS Query** | Each thread executes a DNS lookup for its assigned subdomain using `host` with specified record type and resolver |
| **IV: Filtration** | Intelligent filtering extracts only the requested record type data (A records, CNAME, MX, etc.) |
| **V: Aggregation** | Results are collected and either streamed to console or appended to output file |

**v2.0 Performance:** 10,000 subdomains with 4 threads completes in ~2-3 minutes (vs. 15-20 minutes in v1.0)

### Usage Examples

#### Basic Usage

```bash
# Display help and all available options
sub2ip --help

# Resolve a list of subdomains to the screen
sub2ip subdomains.txt

# Resolve and save clean IPs to a file
sub2ip subdomains.txt -o resolved_ips.txt
```

#### Multi-Threading

```bash
# Use 8 threads for faster processing
sub2ip subdomains.txt -t 8 -o results.txt

# Maximum threads (16) for very large lists
sub2ip massive_list.txt -t 16 -o ips.txt
```

#### DNS Record Types

```bash
# Query IPv4 addresses (A records) - default
sub2ip domains.txt -r A -o ipv4.txt

# Query IPv6 addresses (AAAA records)
sub2ip domains.txt -r AAAA -o ipv6.txt

# Query CNAME records (aliases)
sub2ip domains.txt -r CNAME -o cnames.txt

# Query MX records (mail servers)
sub2ip domains.txt -r MX -o mail_servers.txt

# Query NS records (nameservers)
sub2ip domains.txt -r NS -o nameservers.txt

# Query TXT records
sub2ip domains.txt -r TXT -o txt_records.txt

# Query SOA records
sub2ip domains.txt -r SOA -o soa.txt

# Query all records
sub2ip domains.txt -r ANY -o all_records.txt
```

#### Custom DNS Resolvers

```bash
# Use Google DNS (8.8.8.8)
sub2ip subdomains.txt -s 8.8.8.8 -o results.txt

# Use Cloudflare DNS (1.1.1.1)
sub2ip subdomains.txt -s 1.1.1.1 -o results.txt

# Use Quad9 DNS (9.9.9.9)
sub2ip subdomains.txt -s 9.9.9.9 -o results.txt

# Combine with threads and record type
sub2ip domains.txt -s 8.8.8.8 -r AAAA -t 8 -o ipv6_results.txt
```

#### Advanced Examples

```bash
# Full-featured command: 8 threads, CNAME records, Cloudflare DNS, verbose output
sub2ip domains.txt -t 8 -r CNAME -s 1.1.1.1 -o cnames.txt -v

# Verbose mode for troubleshooting
sub2ip problem_domains.txt -v

# Chain with other tools
cat subfinder_output.txt | sort -u | sub2ip /dev/stdin -t 12 -o final_ips.txt
```
### Output Structure

Depending on your execution mode and record type, the output will vary:

#### Console Output (Real-time)

```text
=====================================
     sub2ip Installation Script     
=====================================

[+] Starting sub2ip resolution engine
[*] Input file: subdomains.txt
[*] Record type: A
[*] Threads: 4
[*] DNS Server: 8.8.8.8

[✓] example.com -> 93.184.216.34
[✓] sub.example.com -> 93.184.216.35
[✓] api.example.com -> 93.184.216.36

[+] Done! Resolution complete!
```

#### File Output (A Records - IPv4)

```text
# resolved_ips.txt
93.184.216.34
93.184.216.35
93.184.216.36
```

#### File Output (CNAME Records)

```text
# cnames.txt
example.com.
sub.example.com.
api.example.com.
```

#### File Output (MX Records)

```text
# mail_servers.txt
mail1.example.com.
mail2.example.com.
```

#### Verbose Output (with -v flag)

```text
[+] Starting sub2ip resolution engine
[*] Input file: domains.txt
[*] Record type: A
[*] Threads: 8
[*] DNS Server: 1.1.1.1

[*] Querying: example.com
[*] Querying: sub.example.com
[*] Querying: api.example.com
[✓] example.com -> 93.184.216.34
[✓] sub.example.com -> 93.184.216.35
[✓] api.example.com -> 93.184.216.36

[+] Done! 3 results saved to: results.txt
```

> [!TIP]
> **Resolution Tip:**
>
> - Feed this tool with massive lists of subdomains harvested from tools like `subfinder`, `gau`, or `assetfinder`.
> - Always verify that `host` is installed and functional on your system before beginning resolution.
> - Utilize the output IP list with subsequent scanning tools like `httpx` or `nmap` for continued reconnaissance.
> - For **v2.0**, use multi-threading (`-t` flag) to dramatically improve performance on large lists.
> - Use custom DNS resolvers (`-s` flag) to bypass filtering or test resolver behavior.
> - Combine with record type filtering (`-r` flag) to gather CNAME records, mail servers, etc.
>
> **Example Pipeline:**
> ```bash
> subfinder -d example.com | sort -u > subdomains.txt
> sub2ip subdomains.txt -t 8 -s 8.8.8.8 -o resolved_ips.txt
> httpx -l resolved_ips.txt -o http_results.txt
> ```

### TO-DO

- [x] Add support for multi-threading (background processing) to increase speed.
  - ✓ Implemented parallel processing with GNU Parallel/xargs
  - ✓ Configurable thread count (1-16)
  - ✓ ~10x faster for large lists

- [x] Implement filtration support for specific record types (e.g., CNAME, AAAA).
  - ✓ Support for A, AAAA, CNAME, MX, NS, TXT, SOA, ANY
  - ✓ Intelligent result filtering per record type
  - ✓ Examples: `sub2ip domains.txt -r AAAA`, `sub2ip domains.txt -r CNAME`

- [x] Integrate support for multiple DNS resolvers.
  - ✓ Custom DNS server support via `-s` / `--server` flag
  - ✓ Tested with Google, Cloudflare, Quad9, and others
  - ✓ Examples: `sub2ip domains.txt -s 8.8.8.8`, `sub2ip domains.txt -s 1.1.1.1`

### Future Enhancements

- [ ] Output format options (JSON, CSV, XML)
- [ ] Rate limiting to respect DNS server load
- [ ] Caching mechanism to prevent duplicate queries
- [ ] Integration with subfinder, gau, assetfinder
- [ ] Distributed processing across multiple machines
- [ ] Real-time progress bar for large batches
- [ ] Batch verification (ping/http check) on resolved IPs

