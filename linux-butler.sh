#! /bin/bash

fin_msg(){
		echo -e "\n\n#################################\n\t$1 DONE\n#################################\n\n"
	}

# checks sudo access
sudo echo || { echo -e "\n\nsudo access denied. run script with a sudoer please."; exit; }

mkdir -p ~/dropzone/github-tools

# Install golang
cd ~/dropzone
sudo apt update
if (which go); then
	fin_msg 'Go installation' 
else
	sudo apt install golang -y
	fin_msg 'GO installation' 
fi

# Download Tools
cd ~/dropzone/github-tools
wget "https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_linux_amd64_1.7.0.zip" && unzip "aquatone_linux_amd64_1.7.0.zip" && fin_msg 'Aquatone' &  # Aquatone
wget "https://github.com/BloodHoundAD/BloodHound/releases/download/4.0.1/BloodHound-linux-x64.zip" && unzip "BloodHound-linux-x64.zip" && fin_msg 'BloodHound' &  # BloodHound
git clone https://github.com/Tib3rius/AutoRecon.git && fin_msg 'AutoRecon' &  # AutoRecon
git clone https://github.com/byt3bl33d3r/CrackMapExec.git & fin_msg 'CrackMapExec' &  # CrackMapExec
git clone https://github.com/Joshua1909/smod.git && fin_msg 'SMOD Framework' &  # SMOD framework
git clone https://github.com/CiscoCXSecurity/enum4linux.git && fin_msg 'enum4linux' &  # enum4linux
git clone https://github.com/carlospolop/privilege-escalation-awesome-scripts-suite.git && fin_msg 'linpeas/winpeas' &  # linpeas/winpeas
git clone https://github.com/OJ/gobuster.git && fin_msg 'Gobuster' &  # Gobuster
git clone https://github.com/sullo/nikto.git && fin_msg 'Nikto Scanner' &  # Nikto
git clone https://github.com/openwall/john.git && fin_msg 'John [Jumbo]' &  # John the Ripper Jumbo

wait
echo -e "\n\nTools pulled successfully.\n\nYou can find them at ~/dropzone/github-tools. Good Luck.\n"

