#!/bin/bash

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="$HOME/ad_install.log"
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
echo "║     PSUT VAPT Team - AD Tools Installation            ║"
echo "║     Installing Active Directory pentesting tools...   ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

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
print_success "Dropzone ready at ~/dropzone"

print_status "Installing AD enumeration and attack tools..."
if sudo apt install -y \
    enum4linux \
    impacket-scripts \
    bloodhound.py \
    docker.io \
    bloodhound \
    neo4j \
    certipy-ad \
    evil-winrm \
    responder; then
    print_success "AD tools installed via APT"
else
    print_warning "Some APT packages may have failed"
fi

print_status "Configuring Neo4j for remote access..."
if [ -f "/etc/neo4j/neo4j.conf" ]; then
    sudo sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/' /etc/neo4j/neo4j.conf
    print_success "Neo4j configured for remote access"
else
    print_warning "Neo4j config file not found, skipping configuration"
fi



print_status "Cloning Ghostpack compiled binaries..."
if [ ! -d "Ghostpack-CompiledBinaries" ]; then
    if git clone https://github.com/r3motecontrol/Ghostpack-CompiledBinaries; then
        bin_count=$(find Ghostpack-CompiledBinaries -name "*.exe" | wc -l)
        print_success "Ghostpack binaries cloned ($bin_count executables)"
        fin_msg 'Ghostpack Compiled Binaries'
    else
        print_warning "Ghostpack binaries clone failed"
    fi
else
    print_success "Ghostpack binaries already exist"
fi

print_status "Installing SharpEfsPotato (requires mono for building)..."
if ! command -v mono &> /dev/null; then
    print_status "Installing mono for C# compilation..."
    sudo apt install -y mono-complete mono-devel
fi

if [ ! -d "SharpEfsPotato" ]; then
    if git clone https://github.com/bugch3ck/SharpEfsPotato; then
        print_success "SharpEfsPotato cloned"
        cd SharpEfsPotato
        if [ -f "SharpEfsPotato.sln" ] || [ -f "*.csproj" ]; then
            print_status "Building SharpEfsPotato with mono..."
            if msbuild SharpEfsPotato.sln 2>/dev/null || xbuild SharpEfsPotato.sln 2>/dev/null; then
                print_success "SharpEfsPotato built successfully"
            else
                print_warning "SharpEfsPotato build failed, check ~/dropzone/SharpEfsPotato for manual build"
            fi
        fi
        cd ~/dropzone
        fin_msg 'SharpEfsPotato'
    else
        print_warning "SharpEfsPotato clone failed"
    fi
else
    print_success "SharpEfsPotato already exists"
fi

print_status "Installing NetExec (NXC)..."
if command -v pipx &> /dev/null; then
    if pipx install git+https://github.com/Pennyw0rth/NetExec 2>&1 | grep -q "installed package"; then
        print_success "NetExec installed via pipx"
        fin_msg 'NetExec (NXC)'
    else
        print_warning "NetExec may already be installed or installation failed"
    fi
else
    print_warning "pipx not found, installing it first..."
    pip install --user pipx --break-system-packages
    python3 -m pipx ensurepath
    pipx install git+https://github.com/Pennyw0rth/NetExec
    print_success "NetExec installed"
    fin_msg 'NetExec (NXC)'
fi

print_status "Installing Certipy-AD..."
if [ ! -d "Certipy" ]; then
    git clone https://github.com/ly4k/Certipy
fi
if pip install certipy-ad --break-system-packages; then
    certipy_version=$(certipy --version 2>&1 || echo "installed")
    print_success "Certipy-AD installed: $certipy_version"
    fin_msg 'Certipy'
else
    print_warning "Certipy-AD installation failed"
fi

print_status "Installing PKINITtools..."
if [ ! -d "PKINITtools" ]; then
    if git clone https://github.com/dirkjanm/PKINITtools; then
        print_success "PKINITtools cloned"
    else
        print_warning "PKINITtools clone failed"
    fi
else
    print_success "PKINITtools already exists"
fi
if pip install minikerberos --break-system-packages; then
    print_success "minikerberos (for PKINITtools) installed"
    fin_msg 'PKINITtools'
else
    print_warning "minikerberos installation failed"
fi

print_status "Installing bloodyAD..."
if [ ! -d "bloodyAD" ]; then
    if git clone https://github.com/CravateRouge/bloodyAD.git; then
        print_success "bloodyAD cloned"
    else
        print_warning "bloodyAD clone failed"
    fi
else
    print_success "bloodyAD already exists"
fi
if [ -d "bloodyAD" ]; then
    cd bloodyAD
    if pip install -r requirements.txt --break-system-packages; then
        print_success "bloodyAD dependencies installed"
    else
        print_warning "bloodyAD dependencies installation failed"
    fi
    cd ~/dropzone
    fin_msg 'bloodyAD'
fi

print_status "Installing Kerbrute..."
if sudo curl -L https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64 -o /usr/local/bin/kerbrute && sudo chmod +x /usr/local/bin/kerbrute; then
    kerbrute_version=$(kerbrute version 2>&1 || echo "installed")
    print_success "Kerbrute installed: $kerbrute_version"
    fin_msg 'Kerbrute'
else
    print_warning "Kerbrute installation failed"
fi

print_status "Installing windapsearch..."
if sudo wget -q https://github.com/ropnop/go-windapsearch/releases/download/v0.3.0/windapsearch-linux-amd64 -O /usr/local/bin/windapsearch && sudo chmod +x /usr/local/bin/windapsearch; then
    print_success "windapsearch installed to /usr/local/bin/windapsearch"
    fin_msg 'windapsearch'
else
    print_warning "windapsearch installation failed"
fi

print_status "Installing Impacket via pipx..."
if ! command -v pipx &> /dev/null; then
    pip install --user pipx --break-system-packages
    python3 -m pipx ensurepath
fi
if python3 -m pipx install impacket; then
    print_success "Impacket installed via pipx"
    fin_msg 'Impacket'
else
    print_warning "Impacket installation may have failed (might already be installed)"
fi

# print_status "Installing Sliver C2 Framework..."
# if ! command -v sliver &> /dev/null; then
#     if curl -s https://sliver.sh/install | sudo bash; then
#         print_success "Sliver installed"

#         if [ -f "/root/sliver-server" ]; then
#             sudo cp /root/sliver-server /usr/bin/ 2>/dev/null || print_warning "Could not copy sliver-server from /root"
#         fi

#         if sudo systemctl enable sliver 2>/dev/null && sudo systemctl start sliver 2>/dev/null; then
#             print_success "Sliver service enabled and started"
#         else
#             print_warning "Sliver service configuration failed (may not have systemd unit)"
#         fi
#         fin_msg 'Sliver C2'
#     else
#         print_warning "Sliver installation failed"
#     fi
# else
#     print_success "Sliver already installed"
#     sliver_version=$(sliver version 2>&1 | head -n1 || echo "installed")
#     print_status "Sliver version: $sliver_version"
# fi

print_status "Installing additional AD Python tools..."
if pip install pypykatz aardwolf --break-system-packages; then
    print_success "pypykatz and aardwolf installed"
else
    print_warning "Some Python AD tools failed to install"
fi

echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     AD Tools Installation Complete!                   ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

print_success "Active Directory tools installed!"
print_success "Tools located at: ~/dropzone"
print_success "Log file: $LOG_FILE"

echo ""
print_status "Running AD tools verification..."
echo ""

AD_PASS=0
AD_FAIL=0

verify_tool() {
    local tool=$1
    if command -v $tool &> /dev/null; then
        print_success "$tool verified"
        ((AD_PASS++))
    else
        print_error "$tool NOT found"
        ((AD_FAIL++))
    fi
}

verify_file() {
    local file=$1
    local desc=$2
    if [ -f "$file" ] || [ -d "$file" ]; then
        print_success "$desc verified"
        ((AD_PASS++))
    else
        print_error "$desc NOT found"
        ((AD_FAIL++))
    fi
}

verify_tool "bloodhound"
verify_tool "neo4j"
verify_tool "evil-winrm"
verify_tool "responder"
verify_tool "enum4linux"
verify_tool "kerbrute"
verify_tool "windapsearch"
verify_tool "certipy-ad"

verify_file "$HOME/dropzone/Ghostpack-CompiledBinaries" "Ghostpack binaries"
verify_file "$HOME/dropzone/SharpEfsPotato" "SharpEfsPotato"
verify_file "$HOME/dropzone/PKINITtools" "PKINITtools"
verify_file "$HOME/dropzone/bloodyAD" "bloodyAD"

python3 -c "import pypykatz" 2>/dev/null && print_success "pypykatz verified" && ((AD_PASS++)) || (print_error "pypykatz NOT working" && ((AD_FAIL++)))

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}AD Tools Verification Summary${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Passed:  $AD_PASS${NC}"
echo -e "${RED}Failed:  $AD_FAIL${NC}"
echo ""

if [ $AD_FAIL -eq 0 ]; then
    print_success "All AD tools verified successfully!"
else
    print_warning "$AD_FAIL AD tools failed verification - check log file"
fi

print_success "Good Luck!"
