#! /bin/bash

mkdir -p ~/dropzone/github-tools
cd ~/dropzone/github-tools
git clone https://github.com/Tib3rius/AutoRecon.git && echo -e "\n\n##################\nAutoRecon DONE\n##################\n\n" &  # AutoRecon
git clone https://github.com/byt3bl33d3r/CrackMapExec.git & echo -e "\n\n##################\nCrackMapExec DONE\n##################\n\n" # CrackMapExec
git clone https://github.com/BloodHoundAD/BloodHound.git && echo -e "\n\n##################\nBloodHound DONE\n##################\n\n" &  # BloodHound
git clone https://github.com/Joshua1909/smod.git && echo -e "\n\n##################\nSMOD DONE\n##################\n\n" &  # SMOD framework
git clone https://github.com/CiscoCXSecurity/enum4linux.git && echo -e "\n\n##################\nenum4linux DONE\n##################\n\n" &  # enum4linux
git clone https://github.com/carlospolop/privilege-escalation-awesome-scripts-suite.git && echo -e "\n\n##################\nlinpeas DONE\n##################\n\n" &  # linpeas/winpeas
git clone https://github.com/OJ/gobuster.git && echo -e "\n\n##################\nGobuster DONE\n##################\n\n" &  # Gobuster
git clone https://github.com/sullo/nikto.git && echo -e "\n\n##################\nNikto DONE\n##################\n\n" &  # Nikto
git clone https://github.com/michenriksen/aquatone.git && echo -e "\n\n##################\nAquatone DONE\n##################\n\n" &  # Aquatone
git clone https://github.com/openwall/john.git && echo -e "\n\n##################\nJohn [Jumbo] DONE\n##################\n\n" &  # John the Ripper Jumbo

wait
echo -e "\n\nTools pulled successfully.\n\nYou can find them at ~/dropzone/github-tools. Good Luck.\n"
