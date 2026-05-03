## sub2ip

<p align="center">
<img width="1024" height="500" alt="image" src="https://github.com/user-attachments/assets/e149af0a-6811-425f-9906-803fc704ccdd" />
</p>

> [!NOTE]
> **sub2ip** is a robust and efficient Bash-based resolution engine designed to convert a list of subdomains into their corresponding IPv4 addresses.

</br>
</br>

### Features

* **Efficient Resolution:** Resolves vast lists of subdomains quickly using the standard `host` utility[cite: 3].
* **Clean IP Extraction:** Automatically strips unnecessary DNS information to output a clean list of IPs (A records)[cite: 3].
* **Intelligent File Handling:** Safely processes input files using line-by-line reading to prevent issues with complex spacing[cite: 3].
* **Flexible Output:** Supports both real-time console display and direct logging to an output file[cite: 3].

</br>
</br>

### Installation

Clone the repository and ensure the script has execution permissions:

```bash
git clone https://github.com/muhammadtaharana/sub2ip
cd sub2ip
chmod +x sub2ip.sh
```

</br>
</br>

### Execution Workflow

The resolution engine processes the input via the following sequential pipeline:

| Phase | Description |
| :--- | :--- |
| **I: Initialization** | Validates the input file and checks for an optional output file path[cite: 3]. |
| **II: Iteration** | Safely reads each subdomain from the input file, line by line[cite: 3]. |
| **III: DNS Query** | Executes a DNS look-up for the subdomain using `host`[cite: 3]. |
| **IV: Filtration** | Identifies and isolates only the lines containing the `IPv4 address` (A records)[cite: 3]. |
| **V: Output** | Either prints results to the screen or appends the clean IP to the specified output file[cite: 3]. |

</br>
</br>

### Usage Examples

- ###### Resolve a list of subdomains to the screen
```bash
./sub2ip.sh subdomains.txt
```

- ###### Resolve and save clean IPs to a file
```bash
./sub2ip.sh subdomains.txt resolved_ips.txt
```

</br>
</br>

### Output Structure

Depending on your execution mode, the output will appear as follows:

- ###### Screen Output (Real-time)
```text
example.com has address 93.184.216.34
sub.example.com has address 93.184.216.35
```

- ###### File Output (`resolved_ips.txt`)
```text
93.184.216.34
93.184.216.35
```

</br>
</br>

> [!TIP]
> **Resolution Tip:**
>
> - Feed this tool with massive lists of subdomains harvested from tools like `subfinder`, `gau`, or `assetfinder`.
> - Always verify that `host` is installed and functional on your system before beginning resolution.
> - Utilize the output IP list with subsequent scanning tools like `httpx` or `nmap` for continued reconnaissance.

</br>
</br>

### TO-DO

* [ ] Add support for multi-threading (background processing) to increase speed[cite: 3].
* [ ] Implement filtration support for specific record types (e.g., CNAME, AAAA).
* [ ] Integrate support for multiple DNS resolvers.

</br>
</br>

> [!CAUTION]
> **Use sub2ip only on assets you own or have explicit permission to test. Unauthorized DNS resolution or subsequent scanning can be illegal. The authors and project accept no responsibility for misuse of this tool.**[cite: 3]
