# windows-mobile.ps1 - PSUT VAPT Team, Android mobile kit for the Windows box.
#
# MOBILE/AI OWNER ONLY.  ~5.9 GB of downloads and well over 10 GB on disk once the
# system images are unpacked. Nobody else should pay for that, which is the same
# reason all.sh gates the equivalent kit behind --mobile.
#
# Two emulators, adb, jadx, frida, Android Studio.
#
# SPLIT OUT OF windows.ps1 ON 2026-10-11, where it was a -Mobile switch. One
# operator needs this kit; everyone else needs Burp and Snaffler. Nothing is shared
# between the two at runtime, so they are two files.
#
# WHY THE EMULATORS LIVE ON WINDOWS AND NOT KALI. all.sh says outright that its
# Android Studio is an APK/layout inspector, not a place to run an app, because the
# emulator needs nested virtualisation a Kali guest will not get. A Windows host can
# expose WHPX, so this is the only box where an emulator might boot - and if THIS
# box is a VM the same ceiling applies, which the check at the end reports.
#
# WHY API 33 MUST NOT HAVE THE PLAY STORE. Google ships three flavours of each
# system image: 'default' (AOSP), 'google_apis' (Google APIs, NO Play Store) and
# 'google_apis_playstore'. Only the first two give you a root shell - on a Play
# Store image 'adb root' is refused outright, because those images ship the
# production verified-boot configuration. No root means no frida-server pushed to
# /data/local/tmp and started, which means no runtime instrumentation, which is
# the entire reason the emulator is here. 'google_apis' is the right pick over
# 'default': it keeps Google Play Services, so apps that need them still run,
# while leaving the image rootable.
#
# ============================== NEEDS INTERNET ==============================
# Chocolatey, pip, Google's SDK repository and a 155 MB direct download all reach
# the public internet, and the system images are another 3.9 GB. On an isolated
# engagement network this script does nothing useful. RUN IT DURING PREP, while
# egress still exists - not on engagement morning.
# ============================================================================
#
# Usage (elevated PowerShell):
#   powershell -ep bypass
#   .\windows-mobile.ps1
#
# IT DOES NOT TOUCH DEFENDER OR THE FIREWALL - windows.ps1 owns that, and this
# script only warns if real-time monitoring is still on. Run windows.ps1 first, or
# turn Defender off by hand: the command-line tools zip is as much a quarantine
# candidate as anything else in the build, and sdkmanager unpacking 3.9 GB of
# system images with real-time scanning enabled is slow enough to look hung.

[CmdletBinding()]
param()

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
Write-Host "|     PSUT VAPT Team - Windows Mobile Kit               |" -ForegroundColor Green
Write-Host "+-------------------------------------------------------+" -ForegroundColor Green
Write-Host ""

# --- elevation -------------------------------------------------------------
# Needed for choco, and for the machine-level ANDROID_SDK_ROOT / ANDROID_HOME.
if (-NOT ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warn "This script needs elevated privileges."
    Write-Warn "Re-run it from an Administrator PowerShell."
    exit 1
}
Write-Ok "Running elevated"

$Transcript = Join-Path $env:USERPROFILE "windows_mobile_install.log"
try { Start-Transcript -Path $Transcript -Append -ErrorAction Stop | Out-Null }
catch { Write-Warn "Could not start a transcript - continuing without one" }

# --- Defender: report, do not change ---------------------------------------
# windows.ps1 owns the Defender and firewall changes, including writing the
# pre-change state out for the Artifact & Configuration Changes sheet. Changing it
# from two scripts would mean two records of the same change, or one overwriting
# the other. So this one only looks: RTM on is not fatal here, it just means the
# 155 MB zip may be taken and 3.9 GB of images will unpack slowly.
$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
if (-not $mp) {
    Write-Warn "Could not read Defender status - treat real-time monitoring as UNKNOWN"
} elseif ($mp.RealTimeProtectionEnabled) {
    Write-Warn "Defender real-time monitoring is ON (IsTamperProtected=$($mp.IsTamperProtected))"
    Write-Warn "  Downloads below may be quarantined and the SDK unpack will be slow."
    Write-Warn "  Run .\windows.ps1 first, which turns it off and records the pre-change state."
} else {
    Write-Ok "Defender real-time monitoring is already off"
}

# ---------------------------------------------------------------------------
# The one download this script makes
# ---------------------------------------------------------------------------
# The standalone Android SDK command-line tools - what gives us sdkmanager and
# avdmanager. We do NOT rely on the SDK that ships inside Android Studio: that one
# is not populated until someone opens the Studio GUI and clicks through its
# first-run wizard, so a script assuming it exists works on a machine someone has
# already used by hand and fails on a fresh one.
#
# Provenance: Google publishes a SHA-1 and a size for this archive in
# repository2-3.xml, not a SHA-256. Both were checked against this download -
# size 154957218 exact, SHA-1 57d04f2d75eb8e8fffc5000a987e5de4b5a63e9d exact - and
# the SHA-256 below was computed from those same verified bytes. URL confirmed to
# resolve 2026-10-05.
#
# ONE artifact, so there is no pin-manifest table here and no pins.lock row.
# windows.ps1 keeps those because it is the script that owns the manifest contract;
# a hashtable lookup to reach a single constant is indirection, not structure.
$CmdToolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip'
$CmdToolsSha = 'e5885e2e59038c0778a85fc19f01de7ce7c567c105553f7617b936b1e0e87b2b'

function Get-Verified {
    <#  Download an artifact and verify it against a known sha256. Two attempts, and
        the partial is DELETED between them - the "already present" check skips on
        any non-empty file, so a half-written zip left behind would be reported
        present on every future run and never completed. #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$Destination
    )
    if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) {
        Write-Ok "$Name already present (skip)"
        return $true
    }
    $ProgressPreference = 'SilentlyContinue'   # 10-50x faster on PowerShell 5.1
    $ok = $false
    foreach ($attempt in 1..2) {
        if ($attempt -gt 1) { Write-Warn "retrying $Name (attempt 2 of 2)..." }
        else { Write-Status "Downloading $Name ..." }
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
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
    # then removed under us - observed on the 2026-10-09 run. Without this check
    # Get-FileHash on a missing path yields $null, $null.ToLower() errors but does
    # not stop the script ($ErrorActionPreference is Continue), and this function
    # would report success for a file that is not there.
    if (-not (Test-Path $Destination) -or
        (Get-Item $Destination -ErrorAction SilentlyContinue).Length -eq 0) {
        Write-Err "$Name vanished after a successful download - antivirus quarantine?"
        Write-Err "  Expected it at: $Destination"
        Write-Err "  Check the Defender status reported above, then re-run."
        return $false
    }

    $hash = Get-FileHash -Path $Destination -Algorithm SHA256 -ErrorAction SilentlyContinue
    if (-not $hash) {
        Write-Err "$Name could not be hashed: $Destination"
        return $false
    }
    if ($hash.Hash.ToLower() -ne $Sha256.ToLower()) {
        Write-Err "$Name SHA256 MISMATCH"
        Write-Err "  expected $Sha256"
        Write-Err "  got      $($hash.Hash.ToLower())"
        Write-Err "  Do NOT use this file until you know why: $Destination"
        return $false
    }
    Write-Ok "$Name verified against pinned sha256"
    return $true
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

# jadx and adb are both real Chocolatey packages (jadx 1.5.6, adb 37.0.0). adb is
# deliberately installed here AS WELL AS arriving with sdkmanager's platform-tools:
# this way a box whose 4.4 GB SDK download failed still has a working adb for a
# physical device, and jadx static analysis needs no SDK at all.
# python3 is here only because frida has no Chocolatey package and has to come from
# pip. temurin17 is for the SDK command-line tools, which are revision 23 and need
# JDK 17+ - see the JDK note further down.
$ChocoPkgs = @('jadx','adb','python3','AndroidStudio','temurin17')

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
# MOBILE KIT
# ---------------------------------------------------------------------------
Write-Status "Installing the Android mobile kit..."

$SdkRoot = 'C:\Android'
$CmdTools = Join-Path $SdkRoot 'cmdline-tools\latest'

# --- frida, from pip: there is no Chocolatey package for it --------------
if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Status "Installing frida-tools (pip)..."
    python -m pip install --upgrade frida-tools 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "frida-tools installed" }
    else { Write-Warn "frida-tools FAILED (pip exit $LASTEXITCODE) - retry: python -m pip install frida-tools" }
} else {
    Write-Warn "python is not on PATH - skipping frida-tools."
    Write-Warn "  Reopen PowerShell and run: python -m pip install frida-tools"
}

# --- Android SDK command-line tools -------------------------------------
if (Test-Path (Join-Path $CmdTools 'bin\sdkmanager.bat')) {
    Write-Ok "Android command-line tools already at $CmdTools (skip)"
} else {
    $ctZip = Join-Path $env:TEMP 'android-cmdline-tools.zip'
    if (Get-Verified -Name 'Android cmdline-tools 23.0 (155 MB)' `
                     -Url $CmdToolsUrl -Sha256 $CmdToolsSha -Destination $ctZip) {
        # The archive unpacks to a bare 'cmdline-tools\' directory, but
        # sdkmanager insists on living at <sdk>\cmdline-tools\<version>\bin -
        # run it from anywhere else and it fails with "Could not determine
        # SDK root". So unpack to a staging dir and move it into place as
        # 'latest'.
        try {
            $stage = Join-Path $env:TEMP 'android-ct-stage'
            Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
            Expand-Archive -Path $ctZip -DestinationPath $stage -Force -ErrorAction Stop
            New-Item -ItemType Directory -Force -Path (Split-Path $CmdTools) | Out-Null
            Move-Item (Join-Path $stage 'cmdline-tools') $CmdTools -Force
            Remove-Item $stage,$ctZip -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Android command-line tools -> $CmdTools"
        } catch {
            Write-Err "Could not unpack the command-line tools: $($_.Exception.Message)"
        }
    }
}

$sdkmanager = Join-Path $CmdTools 'bin\sdkmanager.bat'
$avdmanager = Join-Path $CmdTools 'bin\avdmanager.bat'

if (-not (Test-Path $sdkmanager)) {
    Write-Err "sdkmanager is not present - skipping the SDK packages and both emulators."
} else {
    [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $SdkRoot, 'Machine')
    [Environment]::SetEnvironmentVariable('ANDROID_HOME',     $SdkRoot, 'Machine')
    $env:ANDROID_SDK_ROOT = $SdkRoot
    $env:ANDROID_HOME     = $SdkRoot

    # JAVA_HOME IS CHANGED ONLY FOR THESE CHILD PROCESSES. The command-line
    # tools are revision 23 and need JDK 17+. $env:JAVA_HOME is process-scoped,
    # so pointing it at 17 affects only the children launched below, and it is
    # restored afterwards rather than left changed for whatever runs next.
    # Nothing on this box needs a different JDK now that Neo4j is gone, but the
    # machine-level JAVA_HOME is still deliberately left alone: it is not ours
    # to repoint on a machine the organisers provided.
    $savedJavaHome = $env:JAVA_HOME
    $jdk17 = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -like 'jdk-17*' } |
             Sort-Object Name -Descending | Select-Object -First 1
    if ($jdk17) {
        $env:JAVA_HOME = $jdk17.FullName
        Write-Ok "Using $($jdk17.Name) for the Android tools (machine JAVA_HOME left alone)"
    } else {
        Write-Warn "No JDK 17 found - sdkmanager needs 17 or newer and will probably refuse to run."
        Write-Warn "  Install it: choco install temurin17 -y   then re-run with -Mobile."
    }

    # Licences have to be accepted before anything will download, and
    # sdkmanager --licenses is an interactive y/n prompt per licence. Feeding
    # it a block of 'y' is the standard non-interactive answer.
    Write-Status "Accepting Android SDK licences..."
    $yes = (1..50 | ForEach-Object { 'y' }) -join "`n"
    $yes | & $sdkmanager --licenses --sdk_root="$SdkRoot" 2>&1 | Out-Null

    # x86_64 on purpose. An arm64 image on an x86 host has to be fully
    # emulated rather than virtualised and is unusably slow.
    #
    # API 37.1 exists ONLY as a 'ps16k' variant - the 16 KB page-size images.
    # There is no plain 'system-images;android-37.1;google_apis;x86_64'; the
    # last release with that naming is 37.0. Verified against Google's own
    # sys-img manifest on 2026-10-09, so do not "tidy" the tag away.
    $SdkPkgs = @(
        'platform-tools',
        'emulator',
        'system-images;android-37.1;google_apis_ps16k;x86_64',
        'system-images;android-33;google_apis;x86_64'
    )
    Write-Warn "About to download ~4.4 GB of SDK packages (two system images are 2.2 GB and 1.7 GB)."
    $sdkFailed = @()
    foreach ($pkg in $SdkPkgs) {
        Write-Status "sdkmanager: $pkg"
        & $sdkmanager --sdk_root="$SdkRoot" --install $pkg 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "$pkg installed" }
        else { Write-Warn "$pkg FAILED (sdkmanager exit $LASTEXITCODE)"; $sdkFailed += $pkg }
    }
    if ($sdkFailed.Count -gt 0) {
        Write-Warn "SDK packages that failed: $($sdkFailed -join ', ')"
        Write-Warn "  Retry: & '$sdkmanager' --sdk_root='$SdkRoot' --install '<package>'"
    }

    # --- the two AVDs ---------------------------------------------------
    # -d pixel_6 is passed so avdmanager does not stop and ask whether to
    # build a custom hardware profile; 'no' is piped as a second line of
    # defence in case the profile name is ever retired upstream.
    $Avds = @(
        @{ Name = 'cptc-api371';       Image = 'system-images;android-37.1;google_apis_ps16k;x86_64' },
        @{ Name = 'cptc-api33-noplay'; Image = 'system-images;android-33;google_apis;x86_64' }
    )
    foreach ($avd in $Avds) {
        if ((& $avdmanager list avd 2>&1 | Out-String) -match [regex]::Escape($avd.Name)) {
            Write-Ok "AVD $($avd.Name) already exists (skip)"
            continue
        }
        if ($sdkFailed -contains $avd.Image) {
            Write-Warn "Skipping AVD $($avd.Name) - its system image did not install"
            continue
        }
        Write-Status "Creating AVD $($avd.Name)..."
        'no' | & $avdmanager create avd -n $avd.Name -k $avd.Image -d pixel_6 --force 2>&1 | Out-Null
        # CONFIRMED BY RE-LISTING, not by the exit code. If avdmanager cannot be
        # launched at all, PowerShell throws and $LASTEXITCODE keeps whatever
        # the PREVIOUS command left in it - frequently 0 - so an exit-code test
        # reports success for a tool that never ran - the same class of lie that
        # Get-Verified above guards against by re-checking the file on disk. Asking
        # avdmanager what AVDs exist is one extra call and cannot be fooled.
        if ((& $avdmanager list avd 2>&1 | Out-String) -match [regex]::Escape($avd.Name)) {
            Write-Ok "AVD $($avd.Name) created"
        } else {
            Write-Warn "AVD $($avd.Name) FAILED - it is not in 'avdmanager list avd'"
            Write-Warn "  Retry by hand: & '$avdmanager' create avd -n $($avd.Name) -k '$($avd.Image)' -d pixel_6"
        }
    }

    $env:JAVA_HOME = $savedJavaHome   # leave the process env as we found it

    # --- can an emulator actually run here? ------------------------------
    # Worth answering now rather than on engagement morning. The emulator
    # needs a hypervisor; if this box is itself a VM without nested
    # virtualisation it will install perfectly and then refuse to boot.
    $hv = $false
    try { $hv = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).HypervisorPresent } catch { }
    if (-not $hv) {
        Write-Warn "No hypervisor detected - the emulators may not boot on this box."
        Write-Warn "  Enable Windows Hypervisor Platform, or run the emulators on real hardware."
        Write-Warn "  jadx/adb/frida do not need it; only the emulators do."
    } else {
        Write-Ok "Hypervisor present - hardware acceleration should be available"
    }
}

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

# Each of these RUNS the tool rather than locating it - a jadx.bat that cannot
# find a JVM is on PATH and still useless.
Test-Item "jadx"  { (& jadx --version 2>&1 | Out-String) -match '[0-9]+\.[0-9]' }
Test-Item "adb"   { (& adb version    2>&1 | Out-String) -match 'Android Debug Bridge' }
Test-Item "frida" { (& frida --version 2>&1 | Out-String) -match '[0-9]+\.[0-9]' }
Test-Item "Android Studio installed" {
    [bool](Get-ChildItem 'C:\Program Files\Android\Android Studio\bin\studio*.exe' -ErrorAction SilentlyContinue)
}
Test-Item "sdkmanager" { Test-Path 'C:\Android\cmdline-tools\latest\bin\sdkmanager.bat' }
Test-Item "emulator"   { Test-Path 'C:\Android\emulator\emulator.exe' }
# The images are checked separately from the AVDs: a missing image is WHY an
# AVD would be absent, and conflating the two hides which half broke.
Test-Item "system image API 37.1 (no Play Store)" {
    Test-Path 'C:\Android\system-images\android-37.1\google_apis_ps16k\x86_64'
}
Test-Item "system image API 33 (no Play Store)" {
    Test-Path 'C:\Android\system-images\android-33\google_apis\x86_64'
}
$avdList = try { & 'C:\Android\cmdline-tools\latest\bin\avdmanager.bat' list avd 2>&1 | Out-String } catch { '' }
Test-Item "AVD cptc-api371"       { $avdList -match 'cptc-api371' }
Test-Item "AVD cptc-api33-noplay" { $avdList -match 'cptc-api33-noplay' }

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
Write-Warn "- Reopen PowerShell so ANDROID_SDK_ROOT and the machine PATH are picked up."
Write-Warn "- MOBILE KIT - open a fresh shell first, for ANDROID_SDK_ROOT."
Write-Warn "  List them:  avdmanager list avd"
Write-Warn "  Boot one:   C:\Android\emulator\emulator.exe -avd cptc-api33-noplay"
Write-Warn "  cptc-api33-noplay is the ROOTABLE one - API 33, Google APIs, NO Play"
Write-Warn "  Store - so it is the box frida runs against:"
Write-Warn "      adb root"
Write-Warn "      adb push frida-server /data/local/tmp/"
Write-Warn "      adb shell chmod 755 /data/local/tmp/frida-server"
Write-Warn "      frida-ps -U      # proves the host can see the device"
Write-Warn "  frida-server is deliberately NOT bundled: its version has to match the"
Write-Warn "  frida-tools pip just installed, so grab the matching android-x86_64"
Write-Warn "  build from github.com/frida/frida/releases WHILE YOU STILL HAVE EGRESS."
Write-Warn "  cptc-api371 (API 37.1) is the current-Android target."
Write-Warn "  Static work needs NO emulator: jadx/apktool -> grep -> hand the endpoint"
Write-Warn "  list to the web team. Per the KB that 90-minute path is the one worth"
Write-Warn "  betting on; the emulators are the hedge."
Write-Host ""
Write-Ok "Setup log: $Transcript"
Write-Ok "Good Luck!"

try { Stop-Transcript | Out-Null } catch { }
