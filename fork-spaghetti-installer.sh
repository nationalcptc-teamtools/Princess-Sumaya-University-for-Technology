#! /bin/bash

# A script that exists for no good reason. I dont know why I made it, maybe I'm bored.

fin_msg(){
		echo -e "\n\n#################################\n\t$1 DONE\n#################################\n\n"
	}

# check if it ran before
[ -d "$HOME/dropzone/github-tools" ] && { echo -e "\n\nDropzone directory exists, maybe you ran this before?"; exit; }

# checks sudo access
sudo echo || { echo -e "\n\nsudo access denied. run script with a sudoer please."; exit; }

# Preparations
mkdir -p ~/dropzone/github-tools
cd ~/dropzone
sudo apt update
sudo apt install python3 python3-pip libssl-dev mc tmux seclists curl golang enum4linux gobuster nbtscan nikto nmap onesixtyone oscanner smbclient smbmap smtp-user-enum snmp sslscan sipvicious tnscmd10g whatweb wkhtmltopdf -y 
wait

# Download Tools
cd ~/dropzone/github-tools
fin_msg 'Gobuster' && fin_msg 'Nikto Scanner' && fin_msg 'Seclists install'
sudo python3 -m pip install crackmapexec && fin_msg 'CrackMapExec' &  # CrackMapExec
git clone https://github.com/Tib3rius/AutoRecon.git && sudo python3 -m pip install -r ~/dropzone/github-tools/AutoRecon/requirements.txt && fin_msg 'AutoRecon' &  # AutoRecon
git clone https://github.com/Joshua1909/smod.git && fin_msg 'SMOD Framework' &  # SMOD framework
git clone https://github.com/carlospolop/privilege-escalation-awesome-scripts-suite.git && fin_msg 'linpeas/winpeas' &  # linpeas/winpeas
git clone https://github.com/openwall/john.git && $(cd ~/dropzone/github-tools/john/src && ./configure && make) && fin_msg 'John [Jumbo]' &  # John the Ripper Jumbo
wget "https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_linux_amd64_1.7.0.zip" && unzip "aquatone_linux_amd64_1.7.0.zip" -d ./aquatone && fin_msg 'Aquatone' &  # Aquatone

wait
echo -e "\n\nTools installed successfully.\n\nSome tools are dropped at ~/dropzone/github-tools. Good Luck.\n"

