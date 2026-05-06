# CHANGELOG

All notable changes to the **sub2ip** project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
