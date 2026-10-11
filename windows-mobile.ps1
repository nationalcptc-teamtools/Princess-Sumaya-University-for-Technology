# windows-mobile.ps1 - PSUT VAPT Team, Android mobile kit for the Windows box.
#
# MOBILE/AI OWNER ONLY.  ~6.4 GB of downloads and well over 11 GB on disk once the
# system images are unpacked. Nobody else should pay for that, which is the same
# reason all.sh gates the equivalent kit behind --mobile.
#
# STATIC:   apktool · jadx · dex2jar · apksigner · Ghidra
# DYNAMIC:  two emulators (API 37.1, API 33 no-Play) · adb · frida · Android Studio
#
# The static half is the one the KB says to bet on: APK -> apktool/jadx -> grep ->
# hand the endpoint list to the web team is a ~90 minute path and needs no emulator
# at all. Ghidra is here for the native layer - .so files out of lib/arm64-v8a that
# jadx cannot touch because they are not Dalvik bytecode.
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
#
# ONE JDK SERVES EVERYTHING: temurin21. Ghidra 12 requires JDK 21+ (that floor
# arrived in Ghidra 11.2) and the Android command-line tools require 17+, so 21
# satisfies both and there is no second JDK to juggle. Note choco's ghidra package
# declares NO dependencies - it will install happily and then refuse to launch if
# no JDK 21 is present, which is why this script installs one and checks for it.

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

# dex2jar v2.4, direct from upstream because Chocolatey's package is stuck on 2.0.
# Verified 2026-10-11 on Linux with no antivirus in the path: byte count 19105975
# equals GitHub's reported asset size exactly, the zip passes an integrity test, and
# it unpacks to dex-tools-v2.4/ with 17 top-level .bat launchers including
# d2j-dex2jar.bat. The sha256 was computed from those same verified bytes.
$Dex2JarUrl = 'https://github.com/pxb1988/dex2jar/releases/download/v2.4/dex-tools-v2.4.zip'
$Dex2JarSha = 'ee7c45eb3c1d2474a6145d8d447e651a736a22d9664b6d3d3be5a5a817dda23a'

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

# All five tool packages were confirmed to exist on 2026-10-11 with the versions
# noted. ⚠️ Do NOT check these with the OData `IsLatestVersion` filter - it
# paginates and returns a false negative; that is how temurin11 was once wrongly
# declared missing. `https://community.chocolatey.org/packages/<id>` returning 200,
# or FindPackagesById, is the reliable test.
#
#   apktool  3.0.3   - matches upstream iBotPeaches/Apktool v3.0.3 exactly
#   jadx     1.5.x
#   adb      37.0.0  - deliberately installed here AS WELL AS arriving with
#                      sdkmanager's platform-tools, so a box whose 4.5 GB SDK
#                      download failed still has a working adb for a physical
#                      device. The static tools need no SDK at all.
#   ghidra   12.1.4  - ~400 MB. See the Ghidra note below: it is NOT put on PATH.
#   temurin21 21.0.9 - the single JDK. Ghidra 12 needs 21+, the Android
#                      command-line tools need 17+, so one install covers both.
#
# python3 is here only because frida has no Chocolatey package and has to come from
# pip. dex2jar is NOT here: choco's package is pinned at 2.0 (circa 2015), which
# predates modern multidex and DEX 039 and chokes on an API 33+ APK. Upstream v2.4
# is fetched directly below instead.
$ChocoPkgs = @('apktool','jadx','adb','python3','AndroidStudio','temurin21','ghidra')

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

# --- dex2jar v2.4 --------------------------------------------------------
# DEX -> JAR, so a decompiler that only speaks Java bytecode can read an APK.
# jadx usually makes this unnecessary; it earns its place when jadx fails on
# obfuscated or malformed DEX and you want a second opinion from a different
# decompiler. Unpacked under C:\Android to keep the whole mobile kit in one
# directory - sdkmanager ignores content it does not recognise in the SDK root.
$Dex2Jar = Join-Path $SdkRoot 'dex2jar'
if (Test-Path (Join-Path $Dex2Jar 'd2j-dex2jar.bat')) {
    Write-Ok "dex2jar already at $Dex2Jar (skip)"
} else {
    $djZip = Join-Path $env:TEMP 'dex-tools.zip'
    if (Get-Verified -Name 'dex2jar v2.4 (19 MB)' `
                     -Url $Dex2JarUrl -Sha256 $Dex2JarSha -Destination $djZip) {
        # Unpacks to a versioned 'dex-tools-v2.4\' directory; normalise it so
        # nothing downstream has to know the version string. Same pattern the
        # cmdline-tools use above, and the lookup HAS a failure branch: if the
        # expected directory never appears we say so and KEEP the zip, rather
        # than deleting the only copy and failing later for no visible reason.
        try {
            $stage = Join-Path $env:TEMP 'dex2jar-stage'
            Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
            Expand-Archive -Path $djZip -DestinationPath $stage -Force -ErrorAction Stop
            $inner = Get-ChildItem $stage -Directory |
                     Where-Object { $_.Name -like 'dex-tools-*' } |
                     Select-Object -First 1
            if ($inner) {
                if (Test-Path $Dex2Jar) { Remove-Item $Dex2Jar -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null
                Move-Item $inner.FullName $Dex2Jar -Force
                Remove-Item $stage,$djZip -Recurse -Force -ErrorAction SilentlyContinue
                Write-Ok "dex2jar -> $Dex2Jar"
            } else {
                Write-Err "dex2jar extracted but no dex-tools-* directory appeared under $stage"
                Write-Err "  The zip is still at $djZip - unpack it by hand to $Dex2Jar"
            }
        } catch {
            Write-Err "Could not unpack dex2jar: $($_.Exception.Message)"
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

    # JAVA_HOME IS CHANGED ONLY FOR THESE CHILD PROCESSES. choco's temurin
    # package usually sets it machine-wide, but not reliably before a reboot, so
    # find it ourselves. $env:JAVA_HOME is process-scoped, so this affects only the
    # children launched below and is restored afterwards rather than left changed
    # for whatever runs next. The MACHINE-level JAVA_HOME is deliberately left
    # alone: it is not ours to repoint on a machine the organisers provided.
    #
    # SORTED BY PARSED VERSION, NOT BY NAME. A plain descending name sort is a
    # string sort, which puts jdk-21.0.9 above jdk-21.0.28 because '9' > '2' - so
    # with two JDKs installed it silently picks the older one.
    $savedJavaHome = $env:JAVA_HOME
    $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like 'jdk-21*' } |
           Sort-Object { try { [version](($_.Name -replace '^jdk-', '' -replace '[^0-9.].*$', '').Trim('.')) } catch { [version]'0.0' } } -Descending |
           Select-Object -First 1
    if ($jdk) {
        $env:JAVA_HOME = $jdk.FullName
        Write-Ok "Using $($jdk.Name) for the Android tools (machine JAVA_HOME left alone)"
    } else {
        Write-Warn "No JDK 21 found under Eclipse Adoptium."
        Write-Warn "  sdkmanager needs 17+ and Ghidra 12 needs 21+, so both will refuse to run."
        Write-Warn "  Install it: choco install temurin21 -y   then re-run this script."
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
    #
    # build-tools is where APKSIGNER lives - there is no standalone apksigner
    # package anywhere, on Chocolatey or otherwise, so this is how you get it.
    # 37.0.0 is the newest STABLE build-tools (37.0.0-rc1/rc2 also exist and are
    # deliberately not used), confirmed against Google's repository2-3.xml on
    # 2026-10-11. It also brings zipalign, aapt2 and d8.
    $SdkPkgs = @(
        'platform-tools',
        'emulator',
        'build-tools;37.0.0',
        'system-images;android-37.1;google_apis_ps16k;x86_64',
        'system-images;android-33;google_apis;x86_64'
    )
    Write-Warn "About to download ~4.5 GB of SDK packages (two system images are 2.2 GB and 1.7 GB)."
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

    # --- where Ghidra actually went --------------------------------------
    # CHOCO DOES NOT PUT GHIDRA ON PATH, and this is not a packaging bug - the
    # package's install script walks the unpacked tree and writes a '.ignore' file
    # beside every .exe, which is Chocolatey's way of saying "shim none of these".
    # So there is no `ghidra` command, and a Get-Command check would report FAILED
    # on a perfectly good install. It unzips under the choco lib directory and
    # leaves a Start Menu shortcut pointing at ghidraRun.bat. Print the real path
    # once, here, so nobody has to go looking for it on engagement morning.
    $ghidraRun = Get-ChildItem 'C:\ProgramData\chocolatey\lib\ghidra\tools' -Recurse `
                     -Filter 'ghidraRun.bat' -ErrorAction SilentlyContinue |
                 Select-Object -First 1
    if ($ghidraRun) {
        Write-Ok "Ghidra launcher: $($ghidraRun.FullName)"
        Write-Status "  Also on the Start Menu as 'Ghidra'. It needs JDK 21+ on PATH or JAVA_HOME."
    } else {
        Write-Warn "Ghidra's ghidraRun.bat was not found under C:\ProgramData\chocolatey\lib\ghidra"
        Write-Warn "  Check whether the choco install actually succeeded above."
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
Test-Item "jadx"    { (& jadx --version    2>&1 | Out-String) -match '[0-9]+\.[0-9]' }
Test-Item "apktool" { (& apktool --version 2>&1 | Out-String) -match '[0-9]+\.[0-9]' }
Test-Item "adb"     { (& adb version       2>&1 | Out-String) -match 'Android Debug Bridge' }
Test-Item "frida"   { (& frida --version   2>&1 | Out-String) -match '[0-9]+\.[0-9]' }
# dex2jar and apksigner are checked by PRESENCE, not by running them. Both are
# .bat launchers that print usage to stderr and exit non-zero when given no
# arguments, so "it ran" and "it failed" look identical - a check that cannot
# distinguish them is worse than one that does less and says so honestly.
Test-Item "dex2jar (d2j-dex2jar.bat)" { Test-Path 'C:\Android\dex2jar\d2j-dex2jar.bat' }
Test-Item "apksigner (build-tools 37.0.0)" {
    Test-Path 'C:\Android\build-tools\37.0.0\apksigner.bat'
}
# Ghidra is NOT on PATH by design - see the note in the install block above.
Test-Item "Ghidra (ghidraRun.bat)" {
    [bool](Get-ChildItem 'C:\ProgramData\chocolatey\lib\ghidra\tools' -Recurse `
               -Filter 'ghidraRun.bat' -ErrorAction SilentlyContinue)
}
Test-Item "JDK 21 (java runs, and is 21+)" {
    $j = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like 'jdk-21*' } | Select-Object -First 1
    $j -and ((& (Join-Path $j.FullName 'bin\java.exe') -version 2>&1 | Out-String) -match 'version')
}
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
Write-Warn ""
Write-Warn "- STATIC FIRST. This is the path the KB says to bet on: ~90 minutes, no"
Write-Warn "  emulator, and it hands the web team something they can act on."
Write-Warn "      apktool d app.apk -o app_src      # resources, AndroidManifest, smali"
Write-Warn "      jadx -d app_jadx app.apk          # Java-ish source"
Write-Warn "  Then grep the output for endpoints, keys and hosts and hand the list over:"
Write-Warn '      Get-ChildItem -Recurse app_jadx | Select-String "https?://"'
Write-Warn "  AndroidManifest.xml is where exported activities/receivers/providers and"
Write-Warn "  android:debuggable live - read it before anything else."
Write-Warn ""
Write-Warn "- SECOND OPINION when jadx chokes on obfuscated or malformed DEX:"
Write-Warn "      C:\Android\dex2jar\d2j-dex2jar.bat app.apk    # -> app-dex2jar.jar"
Write-Warn "  then open that jar in any Java decompiler."
Write-Warn ""
Write-Warn "- NATIVE LAYER - Ghidra, for the .so files jadx cannot read because they"
Write-Warn "  are not Dalvik bytecode. Unzip the APK and look in lib\arm64-v8a\."
Write-Warn "  Launch from the Start Menu ('Ghidra'); the path is printed above."
Write-Warn "  NOTE: there is no 'ghidra' command on PATH - that is deliberate on"
Write-Warn "  Chocolatey's part, not a broken install. It needs JDK 21+."
Write-Warn ""
Write-Warn "- RESIGNING a modified APK (apktool b leaves it unsigned and uninstallable):"
Write-Warn "      C:\Android\build-tools\37.0.0\apksigner.bat sign --ks my.keystore app.apk"
Write-Warn "      C:\Android\build-tools\37.0.0\apksigner.bat verify --verbose app.apk"
Write-Warn "  Make a throwaway keystore once with keytool -genkey -v -keystore my.keystore"
Write-Warn ""
Write-Warn "- EMULATORS - the hedge, not the plan."
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
Write-Warn ""
Write-Warn "- Burp for mobile traffic is on this box via windows.ps1. Proxy the emulator"
Write-Warn "  at it with:  emulator -avd <name> -http-proxy 127.0.0.1:8080"
Write-Host ""
Write-Ok "Setup log: $Transcript"
Write-Ok "Good Luck!"

try { Stop-Transcript | Out-Null } catch { }
