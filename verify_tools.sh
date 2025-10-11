#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     PSUT VAPT Team - Tool Verification Script        ║"
echo "║     Checking all installed tools...                  ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

PASS=0
FAIL=0
WARN=0

check_tool() {
    local tool=$1
    local test_cmd=${2:-"$tool --version"}

    if command -v $tool &> /dev/null; then
        if eval "$test_cmd" &> /dev/null; then
            print_success "$tool is working"
            ((PASS++))
        else
            print_warning "$tool is installed but may not be functional"
            ((WARN++))
        fi
    else
        print_error "$tool is NOT installed"
        ((FAIL++))
    fi
}

check_file() {
    local file=$1
    local desc=$2

    if [ -f "$file" ]; then
        print_success "$desc exists at $file"
        ((PASS++))
    else
        print_error "$desc NOT found at $file"
        ((FAIL++))
    fi
}

print_status "Checking core tools..."
check_tool "nmap"
check_tool "masscan"
check_tool "gobuster"
check_tool "ffuf"
check_tool "feroxbuster"
check_tool "dirsearch"

print_status "Checking web application tools..."
check_tool "burpsuite"
check_tool "zaproxy"
check_tool "sqlmap"
check_tool "nikto"
check_tool "wfuzz"
check_tool "whatweb"
check_tool "nuclei"

print_status "Checking network tools..."
check_tool "netcat" "nc -h"
check_tool "socat"
check_tool "proxychains4" "proxychains4 -h"
check_tool "sshuttle"
check_tool "chisel"

print_status "Checking enumeration tools..."
check_tool "enum4linux"
check_tool "nbtscan"
check_tool "smbclient"
check_tool "smbmap"
check_tool "dnsrecon"

print_status "Checking password tools..."
check_tool "hydra"
check_tool "john"
check_tool "hashcat"

print_status "Checking wireless tools..."
check_tool "aircrack-ng"

print_status "Checking exploitation frameworks..."
check_tool "msfconsole" "msfconsole --version"

print_status "Checking forensics tools..."
check_tool "binwalk"
check_tool "steghide"
check_tool "exiftool"
check_tool "wireshark" "wireshark --version"

print_status "Checking screenshot tools..."
check_tool "flameshot"
check_tool "scrot" "scrot --version"
check_tool "maim" "maim --version"

print_status "Checking development tools..."
check_tool "git"
check_tool "python3"
check_tool "pip3" "pip3 --version"
check_tool "docker"
check_tool "docker-compose"
check_tool "go"

print_status "Checking Go tools..."
check_tool "httprobe"
check_tool "waybackurls"
check_tool "subfinder"
check_tool "httpx"

print_status "Checking privilege escalation scripts..."
check_file "$HOME/dropzone/privesc/linpeas.sh" "linpeas.sh"
check_file "$HOME/dropzone/privesc/winpeas.exe" "winpeas.exe"
check_file "$HOME/dropzone/privesc/PowerUp.ps1" "PowerUp.ps1"
check_file "$HOME/dropzone/privesc/privesc.ps1" "privesc.ps1"
check_file "$HOME/dropzone/privesc/PrivescCheck.ps1" "PrivescCheck.ps1"

print_status "Checking additional tools..."
check_file "$HOME/dropzone/pspy64" "pspy64"
check_file "$HOME/dropzone/username-anarchy" "username-anarchy"
check_tool "upshell"

print_status "Checking wordlists..."
check_file "/usr/share/wordlists/rockyou.txt" "rockyou.txt"
if [ -d "/usr/share/wordlists/kali-wordlists" ]; then
    print_success "Kali wordlists directory exists"
    ((PASS++))
else
    print_error "Kali wordlists NOT found"
    ((FAIL++))
fi

print_status "Checking Python packages..."
python3 -c "import requests" 2>/dev/null && print_success "requests module working" && ((PASS++)) || (print_error "requests module NOT working" && ((FAIL++)))
python3 -c "import pwn" 2>/dev/null && print_success "pwntools module working" && ((PASS++)) || (print_error "pwntools module NOT working" && ((FAIL++)))
python3 -c "import bs4" 2>/dev/null && print_success "bs4 module working" && ((PASS++)) || (print_error "bs4 module NOT working" && ((FAIL++)))

print_status "Checking services..."
if systemctl is-active --quiet ssh; then
    print_success "SSH service is running"
    ((PASS++))
else
    print_warning "SSH service is NOT running"
    ((WARN++))
fi

if systemctl is-active --quiet docker; then
    print_success "Docker service is running"
    ((PASS++))
else
    print_warning "Docker service is NOT running"
    ((WARN++))
fi

echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     Verification Summary                              ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}Passed:  $PASS${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo -e "${RED}Failed:  $FAIL${NC}"

TOTAL=$((PASS + WARN + FAIL))
SUCCESS_RATE=$((PASS * 100 / TOTAL))

echo -e "\nSuccess Rate: ${GREEN}${SUCCESS_RATE}%${NC}"

if [ $FAIL -eq 0 ]; then
    echo -e "\n${GREEN}✓ All critical tools are installed and working!${NC}"
    exit 0
elif [ $FAIL -lt 5 ]; then
    echo -e "\n${YELLOW}⚠ Some tools are missing but most are functional${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Multiple tools are missing. Please re-run the installation scripts.${NC}"
    exit 1
fi
