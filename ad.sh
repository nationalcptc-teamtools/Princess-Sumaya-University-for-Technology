#!/bin/bash

fin_msg(){
        echo -e "\n\n#################################\n\t$1 DONE\n#################################\n\n"
    }

sudo apt install -y \
    enum4linux \
    impacket-scripts \
    bloodhound.py\
    docker.io \
    bloodhound \
    neo4j \
    evil-winrm \
    responder 


wait

sudo sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/' /etc/neo4j/neo4j.conf



git clone https://github.com/r3motecontrol/Ghostpack-CompiledBinaries
fin_msg 'Compiled binaries'

pipx install git+https://github.com/Pennyw0rth/NetExec
fin_msg 'NXC -nahya'

git clone https://github.com/ly4k/Certipy
pip install certipy-ad  --break-system-packages
fin_msg 'Certipy'

git clone https://github.com/dirkjanm/PKINITtools
pip install minikerberos  --break-system-packages
fin_msg 'PKINITtools'

git clone https://github.com/CravateRouge/bloodyAD.git
cd bloodyAD
pip install -r requirements.txt --break-system-packages
cd ~/dropzone
fin_msg 'bloodyAD'    


curl -L https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64 -o /usr/local/bin/kerbrute && chmod +x /usr/local/bin/kerbrute && fin_msg 'Kerbrute'

wget https://github.com/ropnop/go-windapsearch/releases/download/v0.3.0/windapsearch-linux-amd64 -O /usr/local/bin/windapsearch && chmod +x /usr/local/bin/windapsearch
fin_msg 'windapsearch'

# Install Impacket
pip install --user pipx --break-system-packages
python3 -m pipx install impacket
fin_msg 'impacket'


# sliver setup

curl https://sliver.sh/install|sudo bash
cp /root/sliver-server /usr/bin
sudo systemctl start sliver
sudo systemctl enable sliver

fin_msg 'sliver - client and server'
