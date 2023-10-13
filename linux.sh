#! /bin/bash

# A script that exists for no good reason. I dont know why I made it, maybe I'm bored.

fin_msg(){
        echo -e "\n\n#################################\n\t$1 DONE\n#################################\n\n"
    }

# check if it ran before
[ -d "$HOME/dropzone" ] && { echo -e "\n\nDropzone directory exists, maybe you ran this before?"; exit; }

# checks sudo access
sudo echo || { echo -e "\n\nsudo access denied. run script with a sudoer please."; exit; }

# Preparations
mkdir -p ~/dropzone
cd ~/dropzone

export DEBIAN_FRONTEND=noninteractive
sudo apt remove needrestart -y
sudo apt update
sudo apt install -y \
    apt-transport-https \
    python3 \
    python3-pip \
    libssl-dev \
    mc \
    seclists \
    curl \
    golang \
    enum4linux \
    gobuster \
    nbtscan \
    nikto \
    nmap \
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
    impacket-scripts \
    bloodhound.py\
    docker.io \
    docker-compose \
    openjdk-11-jdk  \
    shellter \
    evil-winrm \
    john
wait
sudo usermod -aG docker $USER
fin_msg 'apt packages'

# Download jsmith wordlists
git clone https://github.com/insidetrust/statistically-likely-usernames
fin_msg 'jsmith wordlists'


# # Install Neo4j
# wget -O - https://debian.neo4j.com/neotechnology.gpg.key | sudo apt-key add -
# echo 'deb https://debian.neo4j.com stable 4' | sudo tee /etc/apt/sources.list.d/neo4j.list > /dev/null
# sudo apt-get update
# sudo apt-get install neo4j -y
# sudo systemctl stop neo4j
# fin_msg 'neo4j'

# Install Impacket
pip install --user pipx
python3 -m pipx install impacket
fin_msg 'impacket'

# Download Tools
cd ~/dropzone
sudo python3 -m pip install crackmapexec && fin_msg 'CrackMapExec'
git clone https://github.com/Tib3rius/AutoRecon.git && sudo python3 -m pip install -r ~/dropzone/AutoRecon/requirements.txt && fin_msg 'AutoRecon' &  # AutoRecon

mkdir privesc 
curl -L https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh -o ~/dropzone/privesc/linpeas.sh
curl -L https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Privesc/PowerUp.ps1 -o ~/dropzone/privesc/PowerUp.ps1


wget -q https://github.com/BloodHoundAD/BloodHound/releases/download/v4.3.1/BloodHound-linux-x64.zip
unzip BloodHound-linux-x64.zip && fin_msg 'Bloodhound'

curl -L https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64 -o /usr/local/bin/kerbrute && chmod +x /usr/local/bin/kerbrute && fin_msg 'Kerbrute'


git clone https://github.com/ropnop/windapsearch.git
sudo apt-get install build-essential python3-dev \
    libldap2-dev libsasl2-dev slapd ldap-utils tox \
    lcov valgrind -y
pip install python-ldap
fin_msg 'windapsearch'


git clone https://github.com/SpiderLabs/Responder
wget -q "https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_linux_amd64_1.7.0.zip" && unzip "aquatone_linux_amd64_1.7.0.zip" -d ./aquatone && fin_msg 'Aquatone' &  # Aquatone

wait
echo -e "\n\nTools installed successfully.\n\nSome tools are dropped at ~/dropzone. Good Luck.\n"

