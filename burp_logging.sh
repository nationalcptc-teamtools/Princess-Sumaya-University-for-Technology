#!/bin/bash
# Burp Suite HTTP logging setup for CPTC engagements.
#
# Installs a Jython Burp extension (burp_logger.py) that appends one line per
# manual-testing request (Repeater/Intruder/Scanner) to ~/.burp_history_readable.
# Companion to command_logging.sh -- covers the "we're in Burp all day but
# nothing shows up in the shell log" gap for the web team.
#
# What this script does:
#   1. Downloads jython-standalone.jar into ~/.BurpSuite/ (if not present).
#   2. Copies burp_logger.py into ~/.BurpSuite/.
#   3. Best-effort patches UserConfigCommunity.json / UserConfigPro.json so
#      Burp auto-loads the extension on start. A timestamped backup is kept.
#   4. On any structural mismatch (unknown Burp version), falls back to
#      printing one-time manual load instructions.
#
# Usage:  bash burp_logging.sh   (idempotent - safe to re-run)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# WHOSE HOME IS IT?  - duplicated from lib.sh ON PURPOSE
# ---------------------------------------------------------------------------
# This script is standalone: start.sh, all.sh and smol-all.sh all invoke it, and
# it must work without sourcing anything. Keep in step with cptc_user_home() in
# lib.sh.
#
# It writes into the OPERATOR's home. Under sudo, $USER_HOME is /root, so everything
# below would configure root's account and the real user would get none of it -
# while the verification afterwards looked in the real home and reported it
# missing. The home is therefore derived from this script's own path: an operator
# clones the repo into their own home, so the path names them.
_cptc_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cptc_user_home() {
    local dir u home
    dir="$_cptc_script_dir"
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
    # "$HOME", not "$USER_HOME" - this is the LAST resort inside the function that
    # COMPUTES $USER_HOME, so referring to it here is circular: at this point it is
    # either unset (and `set -u` aborts) or empty. lib.sh and the other four copies
    # always had $HOME here; these two drifted. Only reachable when the script is
    # run from outside /home/* with no SUDO_USER, but that is exactly the standalone
    # case these two scripts are written to support.
    printf '%s\n' "$HOME"
}
USER_HOME="${USER_HOME:-$(cptc_user_home)}"
CPTC_USER="$(stat -c %U "$USER_HOME" 2>/dev/null || id -un)"
own_user() {
    [ "$(id -u)" -eq 0 ] || return 0
    [ -n "${CPTC_USER:-}" ] || return 0
    chown -R "$CPTC_USER:" "$@" 2>/dev/null
    return 0
}

BURP_DIR="$USER_HOME/.BurpSuite"
JYTHON_JAR="$BURP_DIR/jython-standalone.jar"
JYTHON_VER="2.7.3"
JYTHON_URL="https://repo1.maven.org/maven2/org/python/jython-standalone/${JYTHON_VER}/jython-standalone-${JYTHON_VER}.jar"
EXT_SRC="$SCRIPT_DIR/burp_logger.py"
EXT_DST="$BURP_DIR/burp_logger.py"
LOG_FILE="$USER_HOME/.burp_history_readable"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_status()  { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_error()   { echo -e "${RED}[-]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

if [ ! -f "$EXT_SRC" ]; then
    print_error "Extension source not found next to this script: $EXT_SRC"
    exit 1
fi

mkdir -p "$BURP_DIR"

# Warn (don't fail) if Burp is currently running. Burp rewrites its user config
# on exit, so any auto-load patch we make now would be clobbered.
if pgrep -f 'burpsuite.*\.jar\|BurpSuite.*Community\|BurpSuite.*Pro' >/dev/null 2>&1; then
    print_warning "Burp Suite appears to be running."
    print_warning "Close it and re-run this script if the extension doesn't stay loaded."
fi

# --- 1. Jython jar ---------------------------------------------------------
if [ ! -f "$JYTHON_JAR" ]; then
    print_status "Downloading Jython ${JYTHON_VER} standalone jar (~40MB)..."
    # THE ONLY BARE curl IN THE REPO, until now. Every other download has at
    # least --retry 2; this one had nothing - no retry, no connect timeout - and
    # a single DNS blip killed it on a teammate's run:
    #     curl: (6) Could not resolve host: repo1.maven.org
    # Without the jython jar the Python extension cannot load at all, so the
    # whole engagement HTTP log was silently absent from that box. In the same
    # run linpeas hit the identical failure (Could not resolve host: github.com)
    # and SURVIVED, because fetch_pinned has --retry 3 - which is the clearest
    # possible argument for putting it here too.
    # --retry-all-errors is included because plain --retry does not cover every
    # resolve/reset case (see the long note in lib.sh's install_burp_latest).
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -C - --retry 5 --retry-all-errors --retry-delay 5 \
             --connect-timeout 15 -o "$JYTHON_JAR.tmp" "$JYTHON_URL" \
             && mv "$JYTHON_JAR.tmp" "$JYTHON_JAR"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=5 --timeout=15 --waitretry=5 -c \
             -O "$JYTHON_JAR.tmp" "$JYTHON_URL" \
             && mv "$JYTHON_JAR.tmp" "$JYTHON_JAR"
    else
        print_error "Neither curl nor wget available. Manual download URL:"
        print_error "  $JYTHON_URL"
        exit 1
    fi
    if [ ! -f "$JYTHON_JAR" ]; then
        print_error "Jython download failed."
        exit 1
    fi
    print_success "Jython jar -> $JYTHON_JAR"
else
    print_success "Jython jar already present ($JYTHON_JAR)"
fi

# --- 2. Extension file ----------------------------------------------------
cp "$EXT_SRC" "$EXT_DST"
print_success "Extension -> $EXT_DST"

# --- 3. Log file ----------------------------------------------------------
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
print_success "Log file  -> $LOG_FILE (mode 0600)"

# --- 4. Auto-load config: patch existing, or seed a fresh file ------------
# Burp stores user options in ~/.BurpSuite/ in THREE sibling files that modern
# Burp writes depending on edition and version:
#   UserConfig.json           -- shared, written by Burp >= mid-2025
#   UserConfigCommunity.json  -- Community-edition, written by every Community build
#   UserConfigPro.json        -- Pro, same role for Pro builds
# All three use the SAME schema today:
#   user_options.extender.python.location_of_jython_standalone_jar_file
#   user_options.extender.extensions (list)
# Earlier code here switched on the filename and wrote a legacy
# user_options.extender.jython_settings.jython_jar for the *Community/*Pro files.
# That schema is NOT what current Burp Community reads, so on a fresh Kali Burp
# would ignore the seed, find no jython jar, and the extension would never load.
# One schema now, used for every filename.
#
# ON PATCH: only touch the files that already exist (the "if any exist" branch).
# ON SEED (fresh Kali, Burp never launched): seed ALL THREE names. Burp
# Community on first launch has been observed to write a defaults-only
# UserConfigCommunity.json and ignore a lone UserConfig.json, dropping our
# extension on the floor. Seeding every filename Burp might look at (and then
# rewrite in place) covers the fresh-profile path at the cost of ~500 bytes.

if ! command -v python3 >/dev/null 2>&1; then
    print_warning "python3 not available; skipping config auto-patch."
    patched_any=0
else
    patched_any=0
    targets=()
    [ -f "$BURP_DIR/UserConfig.json" ]          && targets+=("$BURP_DIR/UserConfig.json")
    [ -f "$BURP_DIR/UserConfigCommunity.json" ] && targets+=("$BURP_DIR/UserConfigCommunity.json")
    [ -f "$BURP_DIR/UserConfigPro.json" ]       && targets+=("$BURP_DIR/UserConfigPro.json")
    if [ ${#targets[@]} -eq 0 ]; then
        targets=(
            "$BURP_DIR/UserConfig.json"
            "$BURP_DIR/UserConfigCommunity.json"
            "$BURP_DIR/UserConfigPro.json"
        )
    fi

    for cfg in "${targets[@]}"; do
        if [ -f "$cfg" ]; then
            backup="$cfg.cptc-bak-$(date +%s)"
            cp "$cfg" "$backup"
            action="Patched"
            note="(backup: $(basename "$backup"))"
        else
            action="Seeded"
            note="(fresh file - Burp had never been launched)"
        fi
        if python3 - "$cfg" "$JYTHON_JAR" "$EXT_DST" <<'PY'
import json, os, sys
cfg_path, jython_jar, ext_path = sys.argv[1], sys.argv[2], sys.argv[3]

if os.path.exists(cfg_path):
    with open(cfg_path) as f:
        cfg = json.load(f)
else:
    cfg = {}

uo = cfg.setdefault("user_options", {})
ex = uo.setdefault("extender", {})

py = ex.setdefault("python", {})
py["location_of_jython_standalone_jar_file"] = jython_jar

exts = ex.setdefault("extensions", [])
# de-dup by extension_file so re-running the installer doesn't stack copies
exts = [e for e in exts if e.get("extension_file") != ext_path]
exts.append({
    "errors": "ui",
    "extension_file": ext_path,
    "extension_type": "python",
    "loaded": True,
    "name": "CPTC Engagement Logger",
    "output": "ui",
    "auto_reload": False,
    "use_ai": False,
})
ex["extensions"] = exts

with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
        then
            print_success "$action $(basename "$cfg") $note"
            patched_any=1
        else
            print_warning "Could not write $(basename "$cfg") (unknown structure)."
        fi
    done
fi

echo
if [ "$patched_any" -eq 1 ]; then
    print_success "Burp will auto-load 'CPTC Engagement Logger' on next start."
    print_status  "Verify: Extensions tab shows it loaded; '$LOG_FILE' grows as you use Repeater/Intruder."
else
    print_warning "Auto-config failed. Do this ONCE inside Burp:"
    print_warning "  1. Settings > Extensions > Python environment > Jython jar file:"
    print_warning "     $JYTHON_JAR"
    print_warning "  2. Extensions > Installed > Add > Type=Python, File=$EXT_DST"
    print_warning "  Burp saves the config on exit; future starts will auto-load."
fi

echo
print_success "Done. Burp HTTP log: $LOG_FILE"
