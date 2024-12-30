#!/bin/bash
sudo echo || { echo -e "\n\nsudo access denied. run script with a sudoer please."; exit; }

sudo apt update
sudo apt install -y \
    python3 \
    python3-pip \
    nmap 

pip3 install argparse requests pwn bs4  --break-system-packages

wget https://raw.githubusercontent.com/zoznoor23/jVision/refs/heads/main/jvisionclient.py
sudo systemctl enable ssh
sudo systemctl start ssh
#sudo apt install -y kali-desktop-xfce xorg xrdp
#sudo systemctl enable xrdp --now
#sudo systemctl start xrdp
