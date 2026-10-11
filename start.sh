#!/bin/bash

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Resolve our own location so we can call sibling scripts regardless of cwd.
# This has to come BEFORE the log file is opened: the home resolver below is what
# decides where the log goes, and under sudo that is not $HOME.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# WHOSE HOME IS IT?  - duplicated from lib.sh ON PURPOSE
# ---------------------------------------------------------------------------
# start.sh deliberately does not source lib.sh: it is the FIRST thing that runs
# on a bare box, so it must work before anything else in the repo is known-good.
# Keep this in step with cptc_user_home() in lib.sh.
#
# Under `sudo bash start.sh`, $HOME is /root - so every dotfile this script's
# helpers write (~/.zshrc, ~/.bashrc, ~/.config/qterminal) would land on root's
# account and the real operator would get no command logging at all. The script
# used to only WARN about that and ask whether to continue. Deriving the home
# from the script's own path fixes it instead: an operator clones this repo into
# their own home, so the path we are executing from names them.
cptc_user_home() {
    local dir u home
    dir="$SCRIPT_DIR"
    if [[ $dir =~ ^/home/([^/]+)(/|$) ]]; then
        u="${BASH_REMATCH[1]}"
        home=$(getent passwd "$u" 2>/dev/null | cut -d: -f6)
        if [ -n "$home" ] && [ -d "$home" ]; then printf '%s\n' "$home"; return 0; fi
        if [ -d "/home/$u" ]; then printf '%s\n' "/home/$u"; return 0; fi
    fi
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        if [ -n "$home" ] && [ -d "$home" ]; then printf '%s\n' "$home"; return 0; fi
    fi
    printf '%s\n' "$HOME"
}
USER_HOME="$(cptc_user_home)"
CPTC_USER="$(stat -c %U "$USER_HOME" 2>/dev/null || id -un)"
export USER_HOME CPTC_USER
own_user() {
    [ "$(id -u)" -eq 0 ] || return 0
    [ -n "${CPTC_USER:-}" ] || return 0
    chown -R "$CPTC_USER:" "$@" 2>/dev/null
    return 0
}

# Every apt call below is non-interactive. DEBIAN_FRONTEND stops debconf asking
# (docker.io's "Remove all Docker data?" is the one that bit us), and the two
# Dpkg::Options stop dpkg asking keep-or-replace when a package ships a changed
# config file. Without both, an install can block forever on a box nobody is
# watching. apt_install in lib.sh does the same thing for all.sh/ad.sh.
export DEBIAN_FRONTEND=noninteractive
# DPkg::Lock::Timeout makes apt WAIT for the dpkg lock instead of failing
# instantly - see the long note in lib.sh's apt_install, which was written after
# five packages were silently lost to a few seconds of lock contention.
# Only force IPv4 when there is no usable IPv6 route. A resolver that returns
# AAAA on a box with no v6 route makes apt hang then fail per package (that is
# how `seclists` died on one teammate's machine), but forcing v4 unconditionally
# would break a genuinely IPv6-only network and we do not know what the
# competition VDI provides. Same logic as lib.sh.
if ip -6 route show default 2>/dev/null | grep -q .; then
    APT_IPV4=""
else
    APT_IPV4="-o Acquire::ForceIPv4=true"
fi
APT_NI=(sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
        -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3 $APT_IPV4)


LOG_FILE="$USER_HOME/start_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
own_user "$LOG_FILE"

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

handle_error() {
    print_error "Error occurred in start.sh at line $1"
    print_error "Check log file: $LOG_FILE"
    exit 1
}

trap 'handle_error $LINENO' ERR

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     PSUT VAPT Team - Initial Setup Script             ║"
echo "║     Starting basic tool installation...               ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# The logging/terminal scripts edit the OPERATOR's dotfiles, not root's. That used
# to make running under sudo dangerous enough to stop and ask about; it no longer
# is, because $USER_HOME above is resolved from this script's path rather than
# from $HOME, so a sudo run still configures the right account. Report the
# situation and carry on - nothing here needs a human to answer.
if [ "$(id -u)" -eq 0 ]; then
    print_warning "Running as root. Installing for '$CPTC_USER' -> $USER_HOME"
    print_warning "  (resolved from this script's path, not \$HOME, which is ${HOME:-unset})"
    print_warning "  Files created here are chown'd back to $CPTC_USER."
fi

print_status "Checking sudo privileges..."
if ! sudo -v; then
    print_error "sudo access denied. Please run this script with sudo privileges."
    exit 1
fi
print_success "Sudo privileges confirmed"

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# needrestart is the package that turns an otherwise silent apt install into an
# interactive "which services should be restarted?" questionnaire. all.sh already
# removes it, but start.sh runs FIRST and installs the desktop, so it has to go
# here or the very first big install is the one that blocks.
print_status "Removing needrestart to avoid interactive prompts..."
sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3 needrestart 2>/dev/null \
    || print_warning "needrestart not installed (ok)"

# Removing it once is not enough. needrestart is a RECOMMENDS of several packages
# we install (docker.io pulls it in; the clean-VM log shows apt listing it under
# "Recommended packages"). On a box where APT::Install-Recommends is true it would
# come straight back, and the very next big apt run - all.sh - becomes the
# interactive questionnaire this whole build exists to avoid. A negative pin is
# the only thing that actually holds.
sudo tee /etc/apt/preferences.d/99-cptc-no-needrestart >/dev/null <<'PIN'
Package: needrestart
Pin: release *
Pin-Priority: -1
PIN
# NOTE: Kali's own `burpsuite` apt package is NOT purged here any more.
# It used to be, and that turned a flaky download into a box with NO Burp at all:
# start.sh purges early, PortSwigger's jar is installed by all.sh much later, and
# on a teammate's run the 653 MB download died at 412 MB
# (curl: (56) Recv failure: Connection reset by peer). Purge first + install
# later = a window in which a network blip leaves the operator with neither copy.
# The purge now happens in all.sh, immediately after install_burp_latest has
# actually succeeded. See the block there.


print_status "Updating package lists..."
if sudo apt-get update -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3; then
    print_success "Package lists updated"
else
    print_error "Failed to update package lists"
    exit 1
fi

# docker.io + docker-compose live HERE, not only in all.sh, so the jVision server
# can be brought up as soon as start.sh finishes - independently of all.sh.
# Why it can't just be done by hand later: all.sh holds the dpkg/apt frontend lock
# for its whole apt phase, so a second terminal running 'apt install docker.io'
# fails with "Could not get lock" until that phase ends. all.sh still lists both
# packages; its apt_install does a dpkg -s check first, so they are a no-op there.
# ONE PACKAGE PER apt-get CALL, and a failure here no longer aborts the script.
# This used to be a single apt-get with all 15 names and `else exit 1`, which
# meant ONE unavailable or broken package took down everything after it - the
# desktop install, the command logging, the terminal uniform - none of which has
# anything to do with the package that failed. The per-package verification loop
# immediately below is what decides whether the box is usable, and it exits 1 on
# a genuinely missing essential. (lib.sh's apt_install does the same thing for
# all.sh; start.sh deliberately does not source lib.sh, so the loop is repeated
# here rather than shared.)
#
# --only-upgrade when the package is already present: a stock Kali ISO ships many
# of these at the version they were frozen at, and apt_install's old `dpkg -s` ->
# skip meant the build never moved them forward. Present-but-older now gets
# upgraded; present-and-current is a fast no-op.
#
# EVERY apt call here RETRIES ONCE. Acquire::Retries (in APT_NI) covers a
# connection failure or a timeout but NOT a definitive HTTP 4xx, which apt treats
# as fatal. Kali's mirror pool is community-run and individual mirrors 403 under
# load: three of seven end-to-end runs lost a package that way, from three
# different mirrors, and in every case a retry seconds later resolved to a
# different mirror and worked. all.sh's apt_install already did this; start.sh
# did not, and start.sh is the worse place to lack it - this list is python3,
# docker.io, build-essential and cmake. A 403 on cmake here is how the unicorn
# wheel build died on run 1, and a 403 on docker.io is a box where jVision cannot
# start and the operator is told to "run all.sh" to find out why.
BASIC_PKGS=(python3 python3-pip python3-venv nmap git curl wget
            docker.io docker-compose python3-pwntools
            build-essential cmake pkg-config ninja-build)
BASIC_FAILED=()
BASIC_STALE=()
apt_retry_once() {   # $1 = label for the message, rest = apt-get install args
    local what=$1; shift
    print_warning "$what failed - retrying once in 5s (community mirrors flake)"
    sleep 5
    "${APT_NI[@]}" "$@"
}
print_status "Installing basic packages (${#BASIC_PKGS[@]} packages, one at a time)..."
for pkg in "${BASIC_PKGS[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        if "${APT_NI[@]}" --only-upgrade "$pkg"; then
            print_success "$pkg present (upgraded if newer was available)"
        elif apt_retry_once "$pkg upgrade" --only-upgrade "$pkg"; then
            print_success "$pkg present (upgraded on retry)"
        else
            print_warning "$pkg present but could not be upgraded (keeping what is there)"
            BASIC_STALE+=("$pkg")
        fi
    elif "${APT_NI[@]}" "$pkg"; then
        print_success "$pkg installed"
    elif apt_retry_once "$pkg" "$pkg"; then
        print_success "$pkg installed (on retry)"
    else
        print_warning "$pkg FAILED to install"
        BASIC_FAILED+=("$pkg")
    fi
done
if [ ${#BASIC_FAILED[@]} -eq 0 ]; then
    print_success "Basic packages installed"
else
    print_warning "Could not install: ${BASIC_FAILED[*]}"
    print_warning "  Continuing - the verification below decides if this box is usable."
fi
if [ ${#BASIC_STALE[@]} -gt 0 ]; then
    print_warning "Left at an older version (upgrade fetch failed twice): ${BASIC_STALE[*]}"
    print_warning "  Retry later: sudo apt install --only-upgrade ${BASIC_STALE[*]}"
fi

print_status "Verifying basic tool installations..."
for tool in python3 pip3 nmap git curl wget; do
    if command -v $tool &> /dev/null; then
        version=$($tool --version 2>&1 | head -n1)
        print_success "$tool is installed: $version"
    else
        print_error "$tool installation failed!"
        exit 1
    fi
done

# Docker post-install, kept non-fatal: a box where docker.io failed should still
# finish setup (all.sh retries it). all.sh does this same usermod - both are no-ops
# on the second run.
if command -v docker &> /dev/null; then
    print_status "Configuring Docker for jVision..."
    if sudo systemctl enable docker --now; then
        print_success "Docker daemon enabled and running"
    else
        print_warning "Could not start the Docker daemon (non-critical)"
    fi
    # "$(id -un)" not "$USER": with 'set -u' an unset USER aborts the script.
    # "$CPTC_USER", not "$(id -un)". Under `sudo bash start.sh` id -un is ROOT, so
    # the docker group was granted to root - who already has it by fiat - and the
    # operator never got it. They then hit "permission denied on
    # /var/run/docker.sock" bringing up jVision and have no idea why, because the
    # build printed "User added to docker group". The earlier comment here was
    # right that "$USER" is unsafe under set -u and wrong that id -un is the
    # answer: $CPTC_USER is resolved from the script's own path.
    if sudo usermod -aG docker "$CPTC_USER"; then
        print_success "User added to docker group (takes effect after re-login)"
    else
        print_warning "Failed to add user to docker group (non-critical)"
    fi
    print_status "Until you re-login, run jVision with: sudo docker-compose ..."
else
    print_warning "docker not present - jVision server cannot start until all.sh installs it"
fi

# NO pip/setuptools SELF-UPGRADE HERE - deliberately removed.
# It used to run `pip install --upgrade pip setuptools`. On a clean Kali VM that
# is run as the operator, so pip says "Defaulting to user installation" and drops
# a NEWER pip and setuptools into ~/.local/lib/pythonX.Y/site-packages, which
# then SHADOWS the distro's copies for every Python process that user starts.
# The clean-VM log shows what that buys: setuptools jumping 78 -> 84 and a
# 24-line wall of "faradaysec requires setuptools<81 ... which is incompatible".
# Kali rolling already ships a current pip (26.1.2 on the test box), so the
# upgrade gained nothing and risked breaking preinstalled Kali tooling.

# argparse is NOT in this list any more either. It has been in the standard
# library since Python 2.7; the PyPI package is a 2012 backport, and installing
# it shadows the stdlib module with a decade-old one.
#
# pwntools NOW COMES FROM APT (python3-pwntools, in the list above), and this pip
# block is only the fallback. Two clean-VM runs were needed to find out why:
#   Run 1: pip pwntools died on  No such file or directory: 'cmake'
#   Run 2: with cmake installed, it died FURTHER IN -
#     src/qemu/util/osdep.c:66: error: implicit declaration of function 'mprotect'
#     src/qemu/util/osdep.c:79: error: 'PROT_READ' undeclared
#     gmake: *** [Makefile:146: all] Error 2
# pwntools depends on `unicorn`, there is no cp314 wheel, so pip builds unicorn
# 2.1.2 from source - and that bundled QEMU code does not compile against
# glibc 2.43 / GCC 15.2 (both now current in Kali), because the newer headers no
# longer pull in <sys/mman.h> transitively. It is not something we can patch.
# Kali packages python3-pwntools 4.15.0-1 - the SAME version pip wanted - built
# against the distro's own python3-unicorn 2.1.4. apt gets a working binary in
# seconds; pip cannot get one at all. Compiling a QEMU fork on every box was
# never the right plan for engagement morning anyway.
#
# Installed ONE AT A TIME, and skipped when the module already imports. pip
# resolves a whole command as ONE transaction: in run 1 the unicorn build failure
# took requests and bs4 with it, because `failed-wheel-build-for-install` aborts
# everything. Separate calls mean one bad wheel costs one package.
print_status "Installing Python packages (requests, beautifulsoup4; pwntools if apt missed it)..."
PY_FAILED=()
for spec in "requests:requests" "bs4:beautifulsoup4" "pwn:pwntools"; do
    mod=${spec%%:*}; pkg=${spec#*:}
    if python3 -c "import $mod" 2>/dev/null; then
        print_success "  $pkg already present (skip)"
    elif python3 -m pip install "$pkg" --break-system-packages; then
        print_success "  $pkg installed"
    else
        print_warning "  $pkg FAILED to install"
        PY_FAILED+=("$pkg")
    fi
done
if [ ${#PY_FAILED[@]} -eq 0 ]; then
    print_success "Python packages installed"
else
    print_warning "Failed to install: ${PY_FAILED[*]} (non-critical - all.sh re-checks)"
fi

# Name the module that is missing. The old version collapsed three imports into
# one `python3 -c` and printed "Some Python packages may not be fully functional"
# - true, useless, and it is the only warning the operator gets before all.sh
# reports the same tool missing an hour later.
print_status "Verifying Python package installations..."
PY_MISSING=()
for mod in requests bs4 pwn; do
    python3 -c "import $mod" 2>/dev/null || PY_MISSING+=("$mod")
done
if [ ${#PY_MISSING[@]} -eq 0 ]; then
    print_success "Python packages verified (requests, bs4, pwn)"
else
    print_warning "Python modules NOT importable: ${PY_MISSING[*]}"
    print_warning "  Retry by hand:  python3 -m pip install <pkg> --break-system-packages"
fi


print_status "Configuring SSH service..."
if sudo systemctl enable ssh && sudo systemctl start ssh; then
    print_success "SSH service enabled and started"
    ssh_status=$(sudo systemctl is-active ssh)
    print_status "SSH Status: $ssh_status"
else
    print_warning "Failed to configure SSH (non-critical)"
fi

print_status "Checking for desktop environment..."
if ! dpkg -l | grep -q kali-desktop-xfce; then
    print_status "Installing XFCE desktop and xRDP (this may take a while)..."
    # Retried for the same reason as the loop above, and it matters more than
    # "non-critical" suggests: no desktop means no xRDP, and xRDP is how the
    # operator reaches Burp's GUI on a VDI box. apt only re-fetches what is
    # missing, so the second attempt is cheap even on a ~1 GB install.
    if "${APT_NI[@]}" kali-desktop-xfce xorg xrdp \
       || apt_retry_once "desktop + xRDP" kali-desktop-xfce xorg xrdp; then
        sudo systemctl enable xrdp --now
        sudo systemctl start xrdp
        print_success "Desktop environment installed and xRDP configured"
    else
        print_warning "Desktop environment installation failed (non-critical)"
        print_warning "  No xRDP means no remote GUI - that is where Burp gets used."
    fi
else
    print_success "Desktop environment already installed"
fi

print_status "Configuring engagement command logging (zsh + bash)..."
if bash "$SCRIPT_DIR/command_logging.sh"; then
    print_success "Command logging configured (readable log: ~/.zsh_history_readable)"
else
    print_warning "Command logging setup reported an issue (non-critical) - see output above"
    print_warning "If it flagged old logging lines, remove them from ~/.zshrc and re-run command_logging.sh"
fi

own_user "$USER_HOME/.zshrc" "$USER_HOME/.bashrc" "$USER_HOME/.zsh_history_readable" 2>/dev/null

print_status "Applying uniform terminal appearance..."
if bash "$SCRIPT_DIR/terminal_uniform.sh"; then
    print_success "Terminal uniform applied (open a fresh qterminal to see it)"
else
    print_warning "Terminal uniform setup reported an issue (non-critical) - see output above"
fi

# NOTE: Burp Suite and its logging extension are NOT configured here any more -
# both moved to all.sh, in that order. burp_logging.sh patches Burp's
# UserConfig*.json so the extension auto-loads, and that file does not exist until
# Burp has been installed and run once. Doing it here, before all.sh installed
# Burp, meant the extension was staged but never registered: the operator started
# Burp, saw no "CPTC Engagement Logger", and nothing explained why.

echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║     Initial Setup Complete!                           ║"
echo "║     Good Luck!!       ~ ziadstr                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
# $LOG_FILE is printed OUTSIDE the box: its length varies with the operator's
# username, so inside the border it blew the box open on the clean-VM run.
echo "      Log file: $LOG_FILE"
echo -e "${NC}"

# --- NEXT STEPS ------------------------------------------------------------
# Everything the operator still has to do by hand: activation of things this
# script *installed* but did not *start*, plus commands that only make sense
# at engagement time (jVision sync, scans).
echo
echo -e "${YELLOW}==============================================================${NC}"
echo -e "${YELLOW}                       NEXT STEPS${NC}"
echo -e "${YELLOW}==============================================================${NC}"

echo
echo -e "${BLUE}[1] Activate command logging${NC} (adds preexec hook to your shell)"
echo "    source $USER_HOME/.zshrc   # or ~/.bashrc, or just open a fresh shell"
echo "    New commands land in $USER_HOME/.zsh_history_readable (timestamps + exit codes)."

echo
echo -e "${BLUE}[2] See the uniform terminal look${NC}"
echo "    Open a NEW qterminal or xfce4-terminal window."
echo "    Windows opened before terminal_uniform.sh ran still show the old look."

echo
echo -e "${BLUE}[3] Install the full tool suite${NC} (heavy; run once per box)"
echo "    bash \"$SCRIPT_DIR/all.sh\""
echo "    Mobile/AI owner only:  bash \"$SCRIPT_DIR/all.sh\" --mobile"
echo "        adds the mobile kit + Android Studio + the nuclei-templates clone"
echo "        (~2.3 GB extra). Everyone else does NOT need it."
echo "    all.sh installs BURP and then wires in the logging extension, so Burp"
echo "    is NOT set up yet at this point - that is expected."
echo "    It re-checks steps [1]-[2], REPORTS anything missing, and continues"
echo "    without asking. Nothing in this build waits for an answer."
echo "    This INCLUDES the AD tooling - there is no separate ad.sh step any more."
echo "        bash \"$SCRIPT_DIR/all.sh\" --ad-only   # AD section only, on a built box"
echo "        bash \"$SCRIPT_DIR/all.sh\" --no-ad      # skip it (~650 MB lighter)"
echo "    Docker is already installed, so [4] can run in a SECOND terminal while"
echo "    this one is still churning through all.sh."

echo
echo -e "${BLUE}[3a] After all.sh: verify Burp auto-loads the CPTC Engagement Logger${NC}"
echo "    burpsuite        # launcher installed by all.sh (picks a JVM >= 21)"
echo "    Extensions tab should show 'CPTC Engagement Logger'."
echo "    Hit Repeater once, then:  tail -f $USER_HOME/.burp_history_readable"

echo
echo -e "${BLUE}[4] Bring up the jVision server${NC} (safe to run alongside all.sh)"
echo "    cd \"$SCRIPT_DIR/jVision\" && sudo docker-compose up -d --build"
echo "    Serves on port 7777. Drop the 'sudo' once you have re-logged in."
echo "    Check it:  sudo docker-compose ps   |   logs: sudo docker-compose logs -f"
echo "    ('docker compose' with a space also works if the CLI plugin is registered.)"

echo
echo -e "${BLUE}[5] AT ENGAGEMENT START -- push your logs to jVision${NC}"
echo "    bash \"$SCRIPT_DIR/jvis_logsync.sh\" start -i <jvision-ip> -u <jvis-user>"
echo "    Control commands:"
echo "        bash \"$SCRIPT_DIR/jvis_logsync.sh\" status"
echo "        bash \"$SCRIPT_DIR/jvis_logsync.sh\" log       # tail daemon log"
echo "        bash \"$SCRIPT_DIR/jvis_logsync.sh\" stop"
echo "    (Prompts for your jVision password; JVIS_PASS env var also works.)"

echo
echo -e "${BLUE}[6] Run scans via the jVision client${NC} (from the jVision repo)"
echo "    sudo python3 jvisionclient.py -i <jvision-ip> -p 7777 -s <target-subnet>"
echo "        -n         only run the heavy scan (skip the fast pass)"
echo "        -u         also run UDP top-50 (SNMP/DNS/NetBIOS etc.)"
echo "    OT/ICS ports are excluded automatically -- do NOT override."

echo
echo -e "${YELLOW}==============================================================${NC}"
echo -e "${GREEN}Setup log: $LOG_FILE${NC}"
echo


