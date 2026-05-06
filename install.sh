#!/bin/bash

# sub2ip Installation Script
# Installs sub2ip globally for system-wide access

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running with sufficient privileges
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
        echo "Usage: sudo ./install.sh [OPTIONS]"
        exit 1
    fi
}

# Display usage
show_usage() {
    echo -e "${GREEN}sub2ip Installation Script${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "    sudo ./install.sh [OPTIONS]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "    -u, --uninstall         Uninstall sub2ip from system"
    echo "    -p, --prefix PATH       Custom installation prefix (default: /usr/local)"
    echo "    -h, --help              Display this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "    # Standard installation"
    echo "    sudo ./install.sh"
    echo ""
    echo "    # Install to custom location"
    echo "    sudo ./install.sh -p /opt"
    echo ""
    echo "    # Uninstall"
    echo "    sudo ./install.sh -u"
    echo ""
    echo -e "${YELLOW}Post-Installation:${NC}"
    echo "    After installation, you can use sub2ip globally:"
    echo "        sub2ip subdomains.txt -o results.txt -t 8"
    echo "        sub2ip domains.txt -r AAAA -s 8.8.8.8"
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--uninstall)
                UNINSTALL=1
                shift
                ;;
            -p|--prefix)
                PREFIX="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Verify script exists
verify_script() {
    if [ ! -f "./sub2ip.sh" ]; then
        echo -e "${RED}Error: sub2ip.sh not found in current directory${NC}"
        echo "Please run this script from the sub2ip repository directory"
        exit 1
    fi

    if [ ! -x "./sub2ip.sh" ]; then
        echo -e "${YELLOW}[*] Making sub2ip.sh executable...${NC}"
        chmod +x ./sub2ip.sh
    fi
}

# Check dependencies
check_dependencies() {
    echo -e "${BLUE}[*] Checking dependencies...${NC}"
    
    local missing=0
    
    # Check for host command
    if ! command -v host &> /dev/null; then
        echo -e "${RED}[!] 'host' command not found${NC}"
        echo "    On Ubuntu/Debian: sudo apt-get install dnsutils"
        echo "    On RHEL/CentOS: sudo yum install bind-utils"
        echo "    On macOS: brew install bind"
        missing=1
    else
        echo -e "${GREEN}[✓] host command${NC}"
    fi
    
    # Check for parallel or xargs
    if ! command -v parallel &> /dev/null && ! command -v xargs &> /dev/null; then
        echo -e "${RED}[!] Neither 'parallel' nor 'xargs' found${NC}"
        echo "    On Ubuntu/Debian: sudo apt-get install moreutils"
        echo "    On RHEL/CentOS: sudo yum install moreutils"
        echo "    On macOS: brew install moreutils"
        missing=1
    else
        if command -v parallel &> /dev/null; then
            echo -e "${GREEN}[✓] GNU Parallel${NC}"
        else
            echo -e "${GREEN}[✓] xargs${NC}"
        fi
    fi

    if [ $missing -eq 1 ]; then
        echo -e "${RED}Please install missing dependencies before continuing${NC}"
        exit 1
    fi
}

# Install sub2ip
install_sub2ip() {
    local prefix="${1:-/usr/local}"
    local install_path="${prefix}/bin/sub2ip"
    
    echo -e "${BLUE}[*] Installing sub2ip to ${install_path}...${NC}"
    
    # Create bin directory if it doesn't exist
    mkdir -p "${prefix}/bin"
    
    # Copy script
    cp ./sub2ip.sh "${install_path}"
    chmod 755 "${install_path}"
    
    # Verify installation
    if [ -x "${install_path}" ]; then
        echo -e "${GREEN}[✓] Installation successful!${NC}"
        echo ""
        echo -e "${BLUE}Quick Start:${NC}"
        echo "  sub2ip --help              Show help and options"
        echo "  sub2ip subdomains.txt      Resolve to screen"
        echo "  sub2ip domains.txt -o ips.txt  Save to file"
        echo "  sub2ip subs.txt -t 8       Use 8 threads"
        echo ""
        return 0
    else
        echo -e "${RED}[!] Installation failed${NC}"
        return 1
    fi
}

# Uninstall sub2ip
uninstall_sub2ip() {
    local prefix="${1:-/usr/local}"
    local install_path="${prefix}/bin/sub2ip"
    
    if [ ! -f "${install_path}" ]; then
        echo -e "${RED}Error: sub2ip not found at ${install_path}${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}[*] Removing sub2ip from ${install_path}...${NC}"
    rm -f "${install_path}"
    
    if [ ! -f "${install_path}" ]; then
        echo -e "${GREEN}[✓] Uninstall successful!${NC}"
        return 0
    else
        echo -e "${RED}[!] Uninstall failed${NC}"
        return 1
    fi
}

# Main execution
main() {
    local UNINSTALL=0
    local PREFIX="/usr/local"
    
    parse_args "$@"
    
    verify_script
    
    if [ $UNINSTALL -eq 1 ]; then
        uninstall_sub2ip "$PREFIX"
    else
        check_dependencies
        install_sub2ip "$PREFIX"
    fi
}

# Run main
main "$@"
