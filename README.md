# PSUT Team Gear

a collection of resources, scripts and tools to aid setting up the testing environment.

## Usage (Linux)

```bash
sudo systemctl start ssh
git clone https://github.com/nationalcptc-teamtools/Princess-Sumaya-University-for-Technology
cd Princess-Sumaya-University-for-Technology
bash start.sh
bash linux.sh
```

## Usage (Windows)

open powershell as admin and run the following command

```powershell
powershell -ep bypass
Invoke-WebRequest -Uri https://raw.githubusercontent.com/nationalcptc-teamtools/Princess-Sumaya-University-for-Technology/master/windows.ps1 -OutFile windows.ps1; .\windows.ps1
```
