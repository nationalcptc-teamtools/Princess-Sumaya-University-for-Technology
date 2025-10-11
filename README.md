# PSUT Red Team Gear

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
**Log File:** `~/start_install.log`

#### 2. Full Linux Toolkit (all.sh)
Installs comprehensive pentesting tools for general assessments.

```bash
bash all.sh
```

**Tools Location:** `~/dropzone`

**Log File:** `~/all_install.log`

#### 3. Active Directory Toolkit (ad.sh)
Specialized tools for Active Directory assessments.

```bash
bash ad.sh
```

**Tools Location:** `~/dropzone`

**Log File:** `~/ad_install.log`

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
