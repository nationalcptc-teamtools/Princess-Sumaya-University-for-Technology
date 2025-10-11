#!/bin/bash
echo "export HISTSIZE=100000" >> ~/.zshrc
echo "export HISTFILESIZE=100000" >> ~/.zshrc
source ~/.zshrc

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
    openjdk-11-jdk  \
    john    \
    awscli \
    sshuttle \
    ffuf \
    burpsuite \
    python3.12-venv \
    nuclei \
    dirsearch \
    flameshot \
    cyberchef

wait
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo usermod -aG docker $USER
fin_msg 'apt packages'

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



# Download Tools
cd ~/dropzone
sudo python3 -m pip install crackmapexec  --break-system-packages && fin_msg 'CrackMapExec'
# git clone https://github.com/Tib3rius/AutoRecon.git && sudo python3 -m pip install -r ~/dropzone/AutoRecon/requirements.txt && fin_msg 'AutoRecon' &  # AutoRecon

mkdir privesc 
curl -L https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh -o ~/dropzone/privesc/linpeas.sh
curl -L https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Privesc/PowerUp.ps1 -o ~/dropzone/privesc/PowerUp.ps1
curl -L https://github.com/peass-ng/PEASS-ng/releases/download/20241011-2e37ba11/winPEASx64.exe  -o ~/dropzone/privesc/winpeas.exe
curl -L https://raw.githubusercontent.com/enjoiz/Privesc/refs/heads/master/privesc.ps1 -o ~/dropzone/privesc/privesc.ps1
curl -L https://raw.githubusercontent.com/itm4n/PrivescCheck/refs/heads/master/PrivescCheck.ps1 -o ~/dropzone/privesc/PrivescCheck.ps1


wget https://github.com/DominicBreuker/pspy/releases/download/v1.2.1/pspy64 
fin_msg 'pspy64' 
wget https://raw.githubusercontent.com/urbanadventurer/username-anarchy/refs/heads/master/username-anarchy 
curl -L https://raw.githubusercontent.com/brightio/penelope/refs/heads/main/extras/tty_upgrade.sh -o /usr/local/bin/upshell 
fin_msg 'upshell' 
wget https://github.com/jpillora/chisel/releases/download/v1.10.1/chisel_1.10.1_linux_amd64.deb -o chisel && chmod +x chisel 
fin_msg 'chisel'


pip install pacu scoutsuite principalmapper minikerberos pypykatz --break-system-packages

sudo git clone https://github.com/00xBAD/kali-wordlists.git && sudo mv kali-wordlists /usr/share/wordlists && sudo gunzip /usr/share/wordlists/rockyou.txt.gz
fin_msg 'Wordlists'

echo "[+] Installing sublime"
echo ""
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt-get update
sudo apt-get install -qq sublime-text
echo ""
echo "[+] sublime installed "

git clone https://github.com/projectdiscovery/nuclei-templates.git
fin_msg 'nuclei templates'

hash -r
wait
echo -e "\n\nTools installed successfully.\n\nSome tools are dropped at ~/dropzone. Good Luck.\n"
