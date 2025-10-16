#!/bin/bash

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="$HOME/all_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

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

fin_msg(){
    echo -e "\n${GREEN}#################################${NC}"
    echo -e "${GREEN}  $1 DONE${NC}"
    echo -e "${GREEN}#################################${NC}\n"
}

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     PSUT VAPT Team - Full Tool Installation           ║"
echo "║     Installing comprehensive pentesting suite...      ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

print_status "Configuring shell history..."
if ! grep -q "HISTSIZE=100000" ~/.zshrc 2>/dev/null; then
    echo "export HISTSIZE=100000" >> ~/.zshrc
    echo "export HISTFILESIZE=100000" >> ~/.zshrc
    print_success "Shell history configured"
else
    print_success "Shell history already configured"
fi

if echo 'preexec() { printf "%s %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$1" >> ~/.zsh_history_readable }' >> ~/.zshrc; then
    print_success "History timestamped"
else 
    print_warning "Timestamping failed"
fi

if xfconf-query -c xfwm4 -p /general/use_compositing -s false ; then
    print_success "Shell display settings configured"
else 
    print_warning "Shell display configuration failed"
fi


if [ -d "$HOME/dropzone" ]; then
    print_warning "Dropzone directory exists, maybe you ran this before?"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled by user"
        exit 1
    fi
    print_status "Continuing with installation..."
fi

print_status "Checking sudo privileges..."
if ! sudo -v; then
    print_error "sudo access denied. run script with a sudoer please."
    exit 1
fi
print_success "Sudo privileges confirmed"

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

print_status "Creating dropzone directory..."
mkdir -p ~/dropzone
cd ~/dropzone
print_success "Dropzone created at ~/dropzone"

export DEBIAN_FRONTEND=noninteractive

print_status "Removing needrestart to avoid prompts..."
sudo apt remove needrestart -y 2>/dev/null || print_warning "needrestart not installed"

print_status "Updating package lists..."
if sudo apt update; then
    print_success "Package lists updated"
else
    print_error "Failed to update packages"
    exit 1
fi

print_status "Installing APT packages (this will take several minutes)..."
if sudo apt install -y \
    apt-transport-https \
    libssl-dev \
    mc \
    seclists \
    curl \
    golang \
    gobuster \
    nbtscan \
    onesixtyone \
    oscanner \
    smbclient \
    smbmap \
    smtp-user-enum \
    snmp \
    sslscan \
    sipvicious \
    tnscmd10g \
    whatweb \
    wkhtmltopdf \
    hashcat \
    feroxbuster \
    dnsrecon \
    redis-tools \
    git \
    wget \
    aircrack-ng \
    set \
    sqlmap \
    hydra \
    docker.io \
    openjdk-11-jdk \
    john \
    awscli \
    sshuttle \
    ffuf \
    burpsuite \
    python3.12-venv \
    nuclei \
    dirsearch \
    flameshot \
    scrot \
    maim \
    cyberchef \
    enum4linux \
    nikto \
    wfuzz \
    steghide \
    binwalk \
    exiftool \
    netcat-traditional \
    socat \
    proxychains4 \
    masscan \
    metasploit-framework \
    responder \
    crackmapexec \
    zaproxy \
    wireshark \
    tcpdump \
    tmux \
    screen \
    remmina \
    terminator; then
    print_success "APT packages installed successfully"
else
    print_warning "Some APT packages may have failed (continuing...)"
fi

print_status "Installing docker-compose..."
if sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose; then
    docker_compose_version=$(docker-compose --version 2>&1)
    print_success "docker-compose installed: $docker_compose_version"
else
    print_warning "docker-compose installation failed (non-critical)"
fi

print_status "Adding user to docker group..."
if sudo usermod -aG docker $USER; then
    print_success "User added to docker group (logout/login required)"
else
    print_warning "Failed to add user to docker group"
fi

fin_msg 'APT packages'

# Download jsmith wordlists
#git clone https://github.com/insidetrust/statistically-likely-usernames
#fin_msg 'jsmith wordlists' 



# git clone https://github.com/NaturalT314/ToolBox
# fin_msg 'NaturalT314 ToolBox'

# # Install Neo4j
# wget -O - https://debian.neo4j.com/neotechnology.gpg.key | sudo apt-key add -
# echo 'deb https://debian.neo4j.com stable 4' | sudo tee /etc/apt/sources.list.d/neo4j.list > /dev/null
# sudo apt-get update
# sudo apt-get install neo4j -y
# sudo systemctl stop neo4j
# fin_msg 'neo4j'



print_status "Creating privesc tools directory..."
mkdir -p ~/dropzone/privesc
cd ~/dropzone

print_status "Downloading privilege escalation scripts..."
if curl -L https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh -o ~/dropzone/privesc/linpeas.sh && \
   curl -L https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Privesc/PowerUp.ps1 -o ~/dropzone/privesc/PowerUp.ps1 && \
   curl -L https://github.com/peass-ng/PEASS-ng/releases/download/20241011-2e37ba11/winPEASx64.exe -o ~/dropzone/privesc/winpeas.exe && \
   curl -L https://raw.githubusercontent.com/enjoiz/Privesc/refs/heads/master/privesc.ps1 -o ~/dropzone/privesc/privesc.ps1 && \
   curl -L https://raw.githubusercontent.com/itm4n/PrivescCheck/refs/heads/master/PrivescCheck.ps1 -o ~/dropzone/privesc/PrivescCheck.ps1; then
    chmod +x ~/dropzone/privesc/linpeas.sh 2>/dev/null
    print_success "Privilege escalation scripts downloaded"
    fin_msg 'Privesc Scripts'
else
    print_warning "Some privilege escalation scripts failed to download"
fi

print_status "Downloading pspy64..."
if wget -q https://github.com/DominicBreuker/pspy/releases/download/v1.2.1/pspy64 -O ~/dropzone/pspy64 && chmod +x ~/dropzone/pspy64; then
    print_success "pspy64 downloaded"
    fin_msg 'pspy64'
else
    print_warning "pspy64 download failed"
fi

print_status "Downloading username-anarchy..."
if wget -q https://raw.githubusercontent.com/urbanadventurer/username-anarchy/refs/heads/master/username-anarchy -O ~/dropzone/username-anarchy && chmod +x ~/dropzone/username-anarchy; then
    print_success "username-anarchy downloaded"
else
    print_warning "username-anarchy download failed"
fi

print_status "Downloading upshell (TTY upgrade helper)..."
if curl -L https://raw.githubusercontent.com/brightio/penelope/refs/heads/main/extras/tty_upgrade.sh -o ~/dropzone/upshell && sudo cp ~/dropzone/upshell /usr/local/bin/upshell && sudo chmod +x /usr/local/bin/upshell; then
    print_success "upshell installed to /usr/local/bin/upshell"
    fin_msg 'upshell'
else
    print_warning "upshell installation failed"
fi

print_status "Downloading chisel..."
if wget -q https://github.com/jpillora/chisel/releases/download/v1.10.1/chisel_1.10.1_linux_amd64.tar.gz -O chisel.tar.gz && \
   tar -xzf chisel.tar.gz && \
   chmod +x chisel && \
   sudo mv chisel /usr/local/bin/chisel; then
    chisel_version=$(chisel --version 2>&1)
    print_success "chisel installed: $chisel_version"
    rm -f chisel.tar.gz
    fin_msg 'chisel'
else
    print_warning "chisel installation failed"
fi


print_status "Installing AWS/Cloud Python packages..."
if pip install pacu scoutsuite principalmapper minikerberos pypykatz --break-system-packages; then
    print_success "AWS/Cloud security tools installed"
    fin_msg 'Cloud Security Tools'
else
    print_warning "Some AWS/Cloud tools failed to install"
fi

print_status "Setting up wordlists..."
if [ ! -d "/usr/share/wordlists/kali-wordlists" ]; then
    if sudo git clone https://github.com/00xBAD/kali-wordlists.git /usr/share/wordlists/kali-wordlists; then
        print_success "Kali wordlists cloned"
    else
        print_warning "Kali wordlists clone failed"
    fi
else
    print_success "Kali wordlists already exist"
fi

if [ -f "/usr/share/wordlists/rockyou.txt.gz" ]; then
    print_status "Extracting rockyou.txt..."
    sudo gunzip /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || print_success "rockyou.txt already extracted"
fi

if [ -f "/usr/share/wordlists/rockyou.txt" ]; then
    rockyou_lines=$(wc -l < /usr/share/wordlists/rockyou.txt)
    print_success "rockyou.txt available ($rockyou_lines lines)"
fi
fin_msg 'Wordlists'

print_status "Installing Sublime Text..."
if wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null && \
   echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null && \
   sudo apt-get update -qq && \
   sudo apt-get install -qq -y sublime-text; then
    subl_version=$(subl --version 2>&1)
    print_success "Sublime Text installed: $subl_version"
    fin_msg 'Sublime Text'
else
    print_warning "Sublime Text installation failed (non-critical)"
fi

print_status "Cloning nuclei templates..."
cd ~/dropzone
if [ ! -d "nuclei-templates" ]; then
    if git clone https://github.com/projectdiscovery/nuclei-templates.git; then
        templates_count=$(find nuclei-templates -name "*.yaml" | wc -l)
        print_success "Nuclei templates cloned ($templates_count templates)"
        fin_msg 'Nuclei Templates'
    else
        print_warning "Nuclei templates clone failed"
    fi
else
    print_success "Nuclei templates already exist"
fi


print_status "Cloning SSTImap"
cd ~/dropzone
if git clone https://github.com/vladko312/SSTImap.git; then
    print_success "SSTImap cloned"
else 
    print_warning "SSTImap clone failed"
fi 


print_status "Installing additional useful Go tools..."
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

if go install github.com/tomnomnom/httprobe@latest 2>/dev/null; then
    print_success "httprobe installed"
fi

if go install github.com/tomnomnom/waybackurls@latest 2>/dev/null; then
    print_success "waybackurls installed"
fi

if go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 2>/dev/null; then
    print_success "subfinder installed"
fi

if go install github.com/projectdiscovery/httpx/cmd/httpx@latest 2>/dev/null; then
    print_success "httpx installed"
fi

print_status "Verifying screenshot tools..."
if command -v flameshot &> /dev/null; then
    flameshot_version=$(flameshot --version 2>&1 | head -n1)
    print_success "Flameshot installed and working: $flameshot_version"
    print_status "Flameshot keybindings: Use 'flameshot gui' or set keyboard shortcut"
else
    print_warning "Flameshot not found"
fi

if command -v scrot &> /dev/null; then
    print_success "scrot installed (alternative screenshot tool)"
fi

if command -v maim &> /dev/null; then
    print_success "maim installed (alternative screenshot tool)"
fi

hash -r

echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     Full Installation Complete!                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

print_success "All tools installed successfully!"
print_success "Tools are located at: ~/dropzone"
print_success "Log file: $LOG_FILE"
print_warning "Note: Logout/login required for docker group changes to take effect"

echo ""
print_status "Running comprehensive tools verification..."
echo ""

PASS=0
FAIL=0
WARN=0

check_tool() {
    local tool=$1
    local test_cmd=${2:-"$tool --version"}

    if command -v $tool &> /dev/null; then
        if eval "$test_cmd" &> /dev/null; then
            print_success "$tool verified"
            ((PASS++))
        else
            print_warning "$tool installed but may not be functional"
            ((WARN++))
        fi
    else
        print_error "$tool NOT installed"
        ((FAIL++))
    fi
}

check_file() {
    local file=$1
    local desc=$2

    if [ -f "$file" ]; then
        print_success "$desc verified"
        ((PASS++))
    else
        print_error "$desc NOT found"
        ((FAIL++))
    fi
}

print_status "Checking core scanning tools..."
check_tool "nmap"
check_tool "masscan"
check_tool "gobuster"
check_tool "ffuf"
check_tool "feroxbuster"

print_status "Checking web tools..."
check_tool "sqlmap"
check_tool "nikto"
check_tool "nuclei"
check_tool "whatweb"

print_status "Checking network tools..."
check_tool "chisel"
check_tool "socat"
check_tool "proxychains4" "proxychains4 -h"

print_status "Checking password tools..."
check_tool "hydra"
check_tool "john"
check_tool "hashcat"

print_status "Checking screenshot tools..."
check_tool "flameshot"
check_tool "scrot" "scrot --version"

print_status "Checking privilege escalation scripts..."
check_file "$HOME/dropzone/privesc/linpeas.sh" "linpeas.sh"
check_file "$HOME/dropzone/privesc/winpeas.exe" "winpeas.exe"
check_file "$HOME/dropzone/pspy64" "pspy64"

print_status "Checking wordlists..."
check_file "/usr/share/wordlists/rockyou.txt" "rockyou.txt"

print_status "Checking Python packages..."
python3 -c "import requests" 2>/dev/null && print_success "requests verified" && ((PASS++)) || (print_error "requests NOT working" && ((FAIL++)))
python3 -c "import pwn" 2>/dev/null && print_success "pwntools verified" && ((PASS++)) || (print_error "pwntools NOT working" && ((FAIL++)))

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Verification Summary${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Passed:  $PASS${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo -e "${RED}Failed:  $FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    print_success "All critical tools verified!"
else
    print_warning "$FAIL tools failed verification - check log file"
fi

print_success "Good Luck!"
