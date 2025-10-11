# PSUT VAPT Team Gear

A comprehensive collection of penetration testing tools and scripts for VAPT assessments. Designed for Kali Linux environments with support for Linux general purpose testing and Active Directory engagements.

## Linux / Kali Installation

### Quick Start

```bash
sudo systemctl start ssh
git clone https://github.com/nationalcptc-teamtools/Princess-Sumaya-University-for-Technology
cd Princess-Sumaya-University-for-Technology
bash start.sh
bash all.sh
```

### Detailed Installation Steps

#### 1. Initial Setup (start.sh)
This script installs basic dependencies and tools needed for all assessments.

```bash
bash start.sh
```

**What it installs:**
- Python 3, pip, and essential libraries (requests, pwntools, beautifulsoup4)
- Nmap for network scanning
- Git, curl, wget
- SSH service configuration
- XFCE desktop environment and xRDP (if not already installed)
- jVision client

**Log File:** `~/start_install.log`

#### 2. Full Linux Toolkit (all.sh)
Installs comprehensive pentesting tools for general assessments.

```bash
bash all.sh
```

**What it installs:**
- **Scanning:** nmap, masscan, gobuster, ffuf, feroxbuster, dirsearch, nuclei
- **Web Testing:** burpsuite, zaproxy, sqlmap, nikto, wfuzz, whatweb
- **Network Tools:** chisel, socat, proxychains4, sshuttle, netcat
- **Password Attacks:** hydra, john, hashcat
- **Exploitation:** metasploit-framework, docker
- **Forensics:** binwalk, steghide, exiftool, wireshark
- **Privilege Escalation Scripts:** linpeas, winpeas, pspy64, PowerUp, PrivescCheck
- **Screenshot Tools:** flameshot, scrot, maim
- **Cloud Security:** pacu, scoutsuite, principalmapper
- **Wordlists:** rockyou.txt, kali-wordlists
- **Go Tools:** httprobe, waybackurls, subfinder, httpx
- **Editors:** Sublime Text, terminator

**Tools Location:** `~/dropzone`

**Log File:** `~/all_install.log`

**Features:**
- Automatic tool verification after installation
- Colored output with progress indicators
- Error handling and logging
- Checks for existing installations to avoid duplicates

#### 3. Active Directory Toolkit (ad.sh)
Specialized tools for Active Directory assessments.

```bash
bash ad.sh
```

**What it installs:**
- **Enumeration:** enum4linux, bloodhound, neo4j, windapsearch
- **Credential Attacks:** responder, kerbrute, pypykatz
- **Exploitation:** evil-winrm, NetExec (CrackMapExec successor), Impacket suite
- **Certificate Attacks:** Certipy-AD
- **Kerberos Attacks:** PKINITtools
- **Privilege Escalation:** bloodyAD, SharpEfsPotato, Ghostpack binaries
- **C2 Framework:** Sliver
- **Post-Exploitation:** aardwolf

**Tools Location:** `~/dropzone`

**Log File:** `~/ad_install.log`

**Features:**
- Neo4j configured for remote access
- Automatic verification of all AD tools
- Mono installation for C# tool compilation

### Tool Verification

After installation, both `all.sh` and `ad.sh` automatically run verification checks. You can also manually verify tools:

```bash
bash verify_tools.sh
```

### Post-Installation

1. **Docker Group:** Logout and login for docker group changes to take effect
2. **Neo4j Setup:** Start neo4j service and set password:
   ```bash
   sudo systemctl start neo4j
   neo4j-admin set-initial-password YourPassword
   ```
3. **Go Tools Path:** Add to your shell RC file:
   ```bash
   echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.zshrc
   source ~/.zshrc
   ```

### Logs and Troubleshooting

All scripts create detailed logs in your home directory:
- `~/start_install.log` - Initial setup log
- `~/all_install.log` - Main toolkit installation log
- `~/ad_install.log` - AD tools installation log

If installation fails, check the relevant log file for errors.

## Windows Installation

Open PowerShell as Administrator and run:

```powershell
powershell -ep bypass
Invoke-WebRequest -Uri https://raw.githubusercontent.com/nationalcptc-teamtools/Princess-Sumaya-University-for-Technology/master/windows.ps1 -OutFile windows.ps1; .\windows.ps1
```

## Tools Included

### Network Scanning & Enumeration
nmap, masscan, gobuster, ffuf, feroxbuster, dirsearch, nbtscan, enum4linux, dnsrecon, smbmap, smbclient

### Web Application Testing
burpsuite, zaproxy, sqlmap, nikto, wfuzz, whatweb, nuclei, httpx, httprobe

### Password Attacks
hydra, john, hashcat, kerbrute, responder

### Active Directory
bloodhound, neo4j, evil-winrm, NetExec, Impacket, Certipy, bloodyAD, PKINITtools, windapsearch, Ghostpack, SharpEfsPotato

### Exploitation & Post-Exploitation
metasploit-framework, Sliver C2, linpeas, winpeas, pspy64, PowerUp, PrivescCheck

### Cloud Security
pacu, scoutsuite, principalmapper, awscli

### Tunneling & Pivoting
chisel, sshuttle, proxychains4, socat

### Forensics & Steganography
binwalk, steghide, exiftool, wireshark, tcpdump

### Utilities
docker, git, tmux, screen, terminator, flameshot, remmina, Sublime Text

## Support

For issues or questions, please open an issue on the GitHub repository.
