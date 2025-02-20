# exit if not admin
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Write-Warning "This script needs elevated privileges!`nPlease re-run this script as an Administrator!" ; exit }


# disable Defender/Firewall because we don't f#$kin care about it 
Get-MpComputerStatus
Set-MpPreference -DisableRealtimeMonitoring $true
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Install chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# windows terminal, openssh, burpsuite
choco install openssh burp-suite-free-edition git flameshot -y

# snaffler
Invoke-WebRequest https://github.com/SnaffCon/Snaffler/releases/download/1.0.135/Snaffler.exe -OutFile ~\Desktop\Snaffler.exe

# BloodHoundAD
Invoke-WebRequest https://github.com/BloodHoundAD/BloodHound/releases/download/v4.3.1/BloodHound-win32-x64.zip -OutFile ~\Desktop\BloodHound.zip 
# unzip
Expand-Archive -Path ~\Desktop\BloodHound.zip -DestinationPath ~\Desktop\BloodHound

# increase putty scrollback
reg add "HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Default%20Settings" /v ScrollbackLines /t REG_DWORD /d 10000 /f

# refresh env
refreshenv
