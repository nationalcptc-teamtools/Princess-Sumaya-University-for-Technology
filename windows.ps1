# windows.ps1 - PSUT VAPT Team, Windows box setup for CPTC engagements.
#
# WHAT THIS BOX IS FOR. Read this before adding anything.
# We do not run active testing from Windows. Its jobs are:
#   1. Burp as the intercepting proxy for dynamic mobile work.
#   2. Share-content hunting with Snaffler.
# Everything offensive runs from Kali. The Windows PAYLOADS (mimikatz, Rubeus,
# PowerView, the potatoes) are NOT installed here - they live in
# ~/dropzone/windows on Kali and get served to compromised targets over HTTP/SMB.
# all.sh builds that set. Do not duplicate it onto this box.
#
# AD GRAPH VISUALISATION LIVES ON KALI, NOT HERE.  Removed from this script
# 2026-10-11. BloodHound 4.3.1 + Neo4j 4.4.19 were installed here as a "backup
# viewer" for Kali's collections. That could never have worked, and the reasoning is
# kept so nobody re-adds it:
#   * Kali runs BloodHound CE 9.x, so its collection zips are CE format.
#   * Legacy 4.3.1 CANNOT ingest a CE zip, CE cannot ingest a legacy one, and no
#     converter exists. A legacy viewer here would have needed its own SEPARATE
#     legacy collection taken on the day - a second pass against the client that
#     nobody owned and nobody would have remembered to run.
#   * CE cannot be stood up here instead: it is a Docker Compose stack needing
#     LINUX containers, and Windows Server cannot provide those. bloodhound-cli is
#     only a wrapper around that same compose stack.
# THE BACKUP IS THEREFORE NOT A SECOND VIEWER, IT IS THE ZIPS THEMSELVES: keep the
# collection zips on the officials-provided drive - which KB 10.0 mandates as the
# only permitted storage for assessment data anyway - and re-ingest on any of the
# other five Kali boxes if one dies. Same format, no conversion, nothing to install.
#
# ============================== NEEDS INTERNET ==============================
# Chocolatey and every download below reach the public internet. On an isolated
# engagement network this script does nothing useful. RUN IT DURING PREP, while
# egress still exists - not on engagement morning.
# ============================================================================
#
# Usage (elevated PowerShell):
#   powershell -ep bypass
#   .\windows.ps1
#
# Switches:
#   -SkipDefender    leave Defender and the firewall alone
#
# THE ANDROID MOBILE KIT IS A SEPARATE SCRIPT: .\windows-mobile.ps1
# Android Studio, the Android SDK, two emulators, adb, jadx and frida used to be a
# -Mobile switch here. It is ~5.9 GB of downloads and well over 10 GB on disk, one
# operator needs it, and it shared nothing with this script at runtime - so it is
# its own file. Run this one first: it is what turns Defender off and records the
# pre-change state.

[CmdletBinding()]
param(
    [switch]$SkipDefender
)

$ErrorActionPreference = 'Continue'

# GitHub and dl.google.com refuse the default TLS on an older Server build, which
# makes every download below fail with an unhelpful "could not create SSL/TLS
# secure channel". Force 1.2 before touching the network.
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-Status  { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn    { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err     { param($m) Write-Host "[-] $m" -ForegroundColor Red }

$script:Pass = 0
$script:Fail = 0

Write-Host ""
Write-Host "+-------------------------------------------------------+" -ForegroundColor Green
Write-Host "|     PSUT VAPT Team - Windows Box Setup                |" -ForegroundColor Green
Write-Host "+-------------------------------------------------------+" -ForegroundColor Green
Write-Host ""

# --- elevation -------------------------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warn "This script needs elevated privileges."
    Write-Warn "Re-run it from an Administrator PowerShell."
    exit 1
}
Write-Ok "Running elevated"

$Transcript = Join-Path $env:USERPROFILE "windows_install.log"
try { Start-Transcript -Path $Transcript -Append -ErrorAction Stop | Out-Null }
catch { Write-Warn "Could not start a transcript - continuing without one" }

# ---------------------------------------------------------------------------
# PIN MANIFEST
# ---------------------------------------------------------------------------
# Same contract as lib.sh on the Kali side: every third-party artifact in one
# place, with the version we intend and the sha256 we expect. "TBD" means
# UNVERIFIED - do not guess one, a wrong hash is worse than no hash.
#
# The hash was computed on 2026-10-09 from a direct download on a Linux box with no
# antivirus in the path, and the file was validated before it was hashed: byte count
# equal to the server's Content-Length, and Snaffler.exe begins MZ. It was
# deliberately NOT taken from a pins.lock produced by a Windows run - Get-Pinned
# could record the hash of a quarantined or truncated file, so harvesting hashes
# from its own output would bake the bug in permanently.
#
# This table DUPLICATES lib.sh's idea rather than sharing it, because PowerShell
# cannot source a bash file. Keep them conceptually in step; nothing enforces it.
# Every URL here was confirmed to resolve on 2026-10-05.
$Pins = @{
    snaffler = @{
        Url     = 'https://github.com/SnaffCon/Snaffler/releases/download/1.0.244/Snaffler.exe'
        Version = '1.0.244'
        Sha256  = '397b22a956545ba9cd5f03f0f61cb16e4760db21be97f979a5cfc059c2f854ca'
    }
}

$PinsLock = Join-Path $env:USERPROFILE "pins.lock"

function Get-Pinned {
    <#  Download a manifest artifact, verify it against the pinned sha256 when the
        manifest has one, and record what actually landed in ~/pins.lock. Diff that
        file between two operators' boxes - any difference is a build that will not
        reproduce. Idempotent: an existing non-empty destination is left alone. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Destination
    )
    $pin = $Pins[$Name]
    if (-not $pin) { Write-Err "Get-Pinned: no manifest entry for '$Name'"; return $false }

    if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) {
        Write-Ok "$(Split-Path $Destination -Leaf) already present (skip)"
        return $true
    }

    # TWO ATTEMPTS, and the partial file is DELETED between them. Both halves
    # matter. On the Kali side a transient mirror fault cost us a package in three
    # of seven end-to-end runs - there is no reason to think Windows is luckier.
    # Deleting the partial is what stops the failure becoming permanent: the skip
    # check above only asks "does a non-empty file exist", so a truncated file left
    # behind would be reported "already present (skip)" on every future run and the
    # operator would never get a complete one.
    $ok = $false
    foreach ($attempt in 1..2) {
        if ($attempt -gt 1) { Write-Warn "retrying $Name (attempt $attempt of 2)..." }
        else { Write-Status "Downloading $Name ($($pin.Version)) ..." }
        try {
            Invoke-WebRequest -Uri $pin.Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
            $ok = $true
            break
        } catch {
            Write-Err "download failed: $Name - $($_.Exception.Message)"
            Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $ok) { return $false }

    # THE FILE CAN BE GONE EVEN THOUGH THE DOWNLOAD "SUCCEEDED". Defender
    # quarantines on write, so Invoke-WebRequest returns cleanly and the file is
    # then removed under us. Observed on the 2026-10-09 run: Snaffler.exe and the
    # BloodHound zip this script used to fetch were BOTH quarantined, this function
    # reported SUCCESS, and the caller failed later at Expand-Archive with an
    # unrelated-looking .ctor error.
    # Without this guard the rest of the function compounds it - Get-FileHash on a
    # missing path yields $null, $null.ToLower() errors but does not stop the
    # script ($ErrorActionPreference is Continue), a NULL hash gets written to
    # pins.lock as though it were a real record, and 'return $true' is still
    # reached. One wrong answer became three.
    if (-not (Test-Path $Destination) -or
        (Get-Item $Destination -ErrorAction SilentlyContinue).Length -eq 0) {
        Write-Err "$Name vanished after a successful download - antivirus quarantine?"
        Write-Err "  Expected it at: $Destination"
        Write-Err "  Check the Defender status reported above, then re-run."
        return $false
    }

    # Null-safe even so: if Get-FileHash fails for any other reason we must not
    # fall through and write an empty hash into the manifest.
    $hash = Get-FileHash -Path $Destination -Algorithm SHA256 -ErrorAction SilentlyContinue
    if (-not $hash) {
        Write-Err "$Name could not be hashed - not recording it: $Destination"
        return $false
    }
    $got = $hash.Hash.ToLower()

    if ($pin.Sha256 -eq 'TBD') {
        Write-Warn "$Name fetched UNVERIFIED (version $($pin.Version), sha256 $($got.Substring(0,16))...)"
    } elseif ($got -eq $pin.Sha256.ToLower()) {
        Write-Ok "$Name verified against pinned sha256"
    } else {
        Write-Err "$Name SHA256 MISMATCH"
        Write-Err "  expected $($pin.Sha256)"
        Write-Err "  got      $got"
        Write-Err "  Do NOT use this file until you know why: $Destination"
        return $false
    }
    "{0}`t{1}`t{2}`t{3}" -f (Get-Date -Format s), $Name, $pin.Version, $got |
        Add-Content -Path $PinsLock
    return $true
}

# ---------------------------------------------------------------------------
# Defender + firewall
# ---------------------------------------------------------------------------
# Why this is here: this box stores and handles offensive tooling, and Defender
# quarantines files like SharpHound on write, which silently breaks a collection
# mid-engagement. The firewall rule is so a listener on this box is reachable from
# our own Kali hosts.
#
# This box does not touch the client, so nothing here is a change to the client's
# environment. It IS a change to a machine the organisers provided, so the
# pre-change state is recorded to disk before anything is altered - that file is
# what makes the change reversible and is what to quote on the Artifact &
# Configuration Changes sheet.
if ($SkipDefender) {
    Write-Status "-SkipDefender given - leaving Defender and the firewall alone"
} else {
    Write-Status "Recording pre-change Defender/firewall state..."
    $stateFile = Join-Path $env:USERPROFILE "pre-change-security-state.txt"
    try {
        "=== Get-MpComputerStatus $(Get-Date -Format s) ===" | Set-Content $stateFile
        Get-MpComputerStatus | Out-String | Add-Content $stateFile
        "=== Get-NetFirewallProfile ===" | Add-Content $stateFile
        Get-NetFirewallProfile | Select-Object Name,Enabled | Out-String | Add-Content $stateFile
        Write-Ok "Pre-change state saved to $stateFile"
    } catch {
        Write-Warn "Could not record pre-change state: $($_.Exception.Message)"
    }

    Write-Status "Disabling Defender real-time monitoring and the firewall..."
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
    } catch {
        Write-Warn "Could not disable Defender RTM: $($_.Exception.Message)"
    }

    # READ IT BACK. Set-MpPreference RETURNS SUCCESS AND SILENTLY DOES NOTHING
    # when Tamper Protection is enabled - it is not an error, so -ErrorAction Stop
    # and the catch above never fire. On a real run this printed "[+] Defender
    # real-time monitoring disabled" and then Defender quarantined two downloads
    # anyway. Asking the service what its state actually is costs one cmdlet, and
    # Get-MpComputerStatus is already called a few lines above for the pre-change
    # record. Same rule as the Kali side: prove it worked, do not assume it did.
    $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if (-not $mp) {
        Write-Warn "Could not read Defender status back - treat RTM as UNKNOWN"
    } elseif ($mp.RealTimeProtectionEnabled) {
        Write-Err "Defender real-time monitoring is STILL ON (IsTamperProtected=$($mp.IsTamperProtected))"
        Write-Err "  Tamper Protection cannot be turned off from PowerShell - it is GUI only:"
        Write-Err "  Windows Security > Virus & threat protection > Manage settings > Tamper Protection"
        Write-Err "  DOWNLOADS BELOW WILL BE QUARANTINED. Turn it off and re-run this script."
    } else {
        Write-Ok "Defender real-time monitoring disabled (confirmed by Get-MpComputerStatus)"
    }

    # Separate switches from RTM, and they were still active on the failed run.
    # SubmitSamplesConsent matters most: left at its default, Defender uploads
    # samples of our tooling to Microsoft for analysis. Non-fatal - a box where
    # these do not apply is still usable.
    try { Set-MpPreference -SubmitSamplesConsent NeverSend -ErrorAction Stop
          Write-Ok "Sample submission set to NeverSend" }
    catch { Write-Warn "Could not set SubmitSamplesConsent: $($_.Exception.Message)" }

    try { Set-MpPreference -MAPSReporting Disabled -ErrorAction Stop
          Write-Ok "MAPS cloud reporting disabled" }
    catch { Write-Warn "Could not set MAPSReporting: $($_.Exception.Message)" }

    try { Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction Stop
          Write-Ok "Block-at-first-seen disabled" }
    catch { Write-Warn "Could not set DisableBlockAtFirstSeen: $($_.Exception.Message)" }
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction Stop
        Write-Ok "Firewall disabled on all three profiles"
    } catch {
        Write-Warn "Could not disable the firewall: $($_.Exception.Message)"
    }
    Write-Warn "To restore:  Set-MpPreference -DisableRealtimeMonitoring `$false"
    Write-Warn "             Set-MpPreference -SubmitSamplesConsent AlwaysPrompt -MAPSReporting Advanced"
    Write-Warn "             Set-MpPreference -DisableBlockAtFirstSeen `$false"
    Write-Warn "             Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True"
    Write-Warn "  Pre-change values are in $stateFile - that file is the record for the"
    Write-Warn "  Artifact & Configuration Changes sheet."
}

# ---------------------------------------------------------------------------
# Chocolatey + packages
# ---------------------------------------------------------------------------
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Ok "Chocolatey already installed"
} else {
    Write-Status "Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
        Write-Ok "Chocolatey installed"
    } catch {
        Write-Err "Chocolatey install failed: $($_.Exception.Message)"
        Write-Err "Everything below depends on it. Check egress and re-run."
    }
}

# Refresh PATH in-process so choco is callable without reopening the shell.
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')

# burp-suite-free-edition is Burp COMMUNITY. Burp Pro is banned by the rules;
# do not swap this for the pro package.
$ChocoPkgs = @('openssh','burp-suite-free-edition','git','flameshot','greenshot')
if (Get-Command choco -ErrorAction SilentlyContinue) {
    # One package at a time, so a single failure is reported and skipped instead
    # of taking the whole batch with it. Same reasoning as apt_install in lib.sh.
    $failed = @()
    foreach ($pkg in $ChocoPkgs) {
        Write-Status "choco install $pkg"
        choco install $pkg -y --no-progress | Out-Null
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1641 -or $LASTEXITCODE -eq 3010) {
            Write-Ok "$pkg installed"
        } else {
            Write-Warn "$pkg FAILED (choco exit $LASTEXITCODE)"
            $failed += $pkg
        }
    }
    # REFRESH PATH AGAIN, AFTER the loop. The refresh above runs before anything
    # is installed - it is there so 'choco' itself is callable right after a fresh
    # Chocolatey install - which means every tool installed in this loop is absent
    # from the in-process PATH. On a real run that produced "[+] git installed"
    # followed by "[-] git FAILED" from the verification pass thirty lines later.
    # A false FAIL is worse than no check: it is how people learn to ignore the
    # checker, and then they ignore a true one.
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')

    if ($failed.Count -gt 0) {
        Write-Warn "Chocolatey packages that failed: $($failed -join ', ')"
        Write-Warn "  Retry: choco install $($failed -join ' ') -y"
    }
}

# ---------------------------------------------------------------------------
# Snaffler
# ---------------------------------------------------------------------------
# Share-content hunting. Worth having on a theme-park estate specifically: a flat,
# aging network with an overworked generalist admin is where credentials in share
# files actually live. Single binary, run from Desktop.
$desktop = [Environment]::GetFolderPath('Desktop')

# A OneDrive-redirected Desktop syncs everything written here to Microsoft's
# cloud, which scans it server-side no matter what Defender is told locally. On a
# real run that is where Snaffler.exe went. Worth one check: this is a warning,
# not a blocker, because the provided VDI boxes are domain-joined Server and will
# not hit it - a teammate's own laptop during prep will.
if ($env:OneDrive -and $desktop.StartsWith($env:OneDrive, 'OrdinalIgnoreCase')) {
    Write-Warn "Your Desktop is REDIRECTED INTO ONEDRIVE: $desktop"
    Write-Warn "  Tooling written there syncs to Microsoft and is scanned in the cloud,"
    Write-Warn "  which no local Defender setting can prevent. Expect quarantine."
    Write-Warn "  Pause OneDrive sync, or re-run with -SkipDefender and place tools by hand."
}
Get-Pinned -Name snaffler -Destination (Join-Path $desktop 'Snaffler.exe') | Out-Null

# ---------------------------------------------------------------------------
# PuTTY scrollback
# ---------------------------------------------------------------------------
# 10k lines instead of the 200-line default. Cheap, and it is the difference
# between having and not having the evidence of a long session.
Write-Status "Raising the PuTTY scrollback limit..."
reg add "HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Default%20Settings" `
    /v ScrollbackLines /t REG_DWORD /d 10000 /f | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Ok "PuTTY scrollback set to 10000" }
else { Write-Warn "Could not set the PuTTY scrollback value" }

# ---------------------------------------------------------------------------
# VERIFICATION
# ---------------------------------------------------------------------------
# Same contract as all.sh: prove the thing WORKS, do not just locate it.
Write-Host ""
Write-Status "Verifying..."

function Test-Item {
    param([string]$Desc, [scriptblock]$Check)
    try {
        if (& $Check) { Write-Ok "$Desc verified"; $script:Pass++ }
        else { Write-Err "$Desc FAILED"; $script:Fail++ }
    } catch {
        Write-Err "$Desc FAILED ($($_.Exception.Message))"; $script:Fail++
    }
}

# A download that came back as a captive-portal login page still has a 200 status
# and a plausible size. A real PE starts with "MZ"; that is the cheap tell.
function Test-PE {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    # Read the two magic bytes through .NET rather than Get-Content: the PowerShell
    # way needs -Encoding Byte on 5.1 (what Windows Server ships) and -AsByteStream
    # on 7, so either spelling breaks on the other host. A FileStream works on both.
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $b = New-Object byte[] 2
            if ($fs.Read($b, 0, 2) -ne 2) { return $false }
            return ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)
        } finally { $fs.Dispose() }
    } catch { return $false }
}

Test-Item "Chocolatey"  { [bool](Get-Command choco -ErrorAction SilentlyContinue) }
Test-Item "git"         { [bool](Get-Command git   -ErrorAction SilentlyContinue) }
Test-Item "Burp Community" {
    [bool](Get-ChildItem 'C:\Program Files*\BurpSuiteCommunity*' -ErrorAction SilentlyContinue) -or
    [bool](Get-Command 'BurpSuiteCommunity' -ErrorAction SilentlyContinue)
}
Test-Item "Snaffler.exe (valid PE)" { Test-PE (Join-Path $desktop 'Snaffler.exe') }

Write-Host ""
Write-Host "=======================================" -ForegroundColor Green
Write-Host "Verification Summary"                    -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green
Write-Host "Passed: $script:Pass" -ForegroundColor Green
Write-Host "Failed: $script:Fail" -ForegroundColor Red
Write-Host ""

if ($script:Fail -eq 0) { Write-Ok "All checks passed." }
else { Write-Warn "$script:Fail check(s) failed - see above and the transcript at $Transcript" }

Write-Host ""
Write-Host "+-------------------------------------------------------+" -ForegroundColor Yellow
Write-Host "|   NEXT STEPS                                          |" -ForegroundColor Yellow
Write-Host "+-------------------------------------------------------+" -ForegroundColor Yellow
Write-Warn "- Reopen PowerShell so the machine PATH is picked up."
Write-Warn "- AD GRAPH VISUALISATION IS ON KALI, not on this box. BloodHound CE 9.x"
Write-Warn "  owns it. The backup is the collection ZIPS, not a second viewer: keep them"
Write-Warn "  on the officials-provided drive - KB 10.0 makes that the only permitted"
Write-Warn "  storage for assessment data anyway - and re-ingest on any of the other"
Write-Warn "  five Kali boxes if one dies. A legacy BloodHound here could not have read"
Write-Warn "  a CE zip at all, which is why it is no longer installed. See the header."
Write-Warn "- Offensive payloads are NOT on this box by design - they live in"
Write-Warn "  ~/dropzone/windows on Kali and are served from there. See all.sh."
Write-Warn "- The Android mobile kit is a SEPARATE script: .\windows-mobile.ps1"
Write-Warn "  Mobile/AI owner only - ~5.9 GB down, 10 GB+ on disk. Run it after this."
if (-not $SkipDefender) {
    Write-Warn "- Defender RTM and the firewall are OFF. Pre-change state is in"
    Write-Warn "  $env:USERPROFILE\pre-change-security-state.txt - log this on the"
    Write-Warn "  Artifact & Configuration Changes sheet."
}
Write-Host ""
Write-Ok "Setup log: $Transcript"
if (Test-Path $PinsLock) { Write-Status "What this box actually downloaded: $PinsLock" }
Write-Ok "Good Luck!"

try { Stop-Transcript | Out-Null } catch { }
