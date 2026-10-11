#!/bin/bash
# Terminal uniform for CPTC engagements.
# Makes every teammate's terminal look identical so report screenshots match, for
# BOTH terminals in play on our boxes:
#   - qterminal        (Kali's default local terminal)
#   - xfce4-terminal   (the terminal in the XFCE/xRDP remote session start.sh sets up)
#
# Applied look (identical on both emulators):
#   - opaque solid-black background  (no wallpaper/transparency bleed in screenshots)
#   - green-on-black text            (unchanged - #18b218, the old GreenOnBlack foreground)
#   - FiraCode 10                    (Kali's default font, pinned so it can't drift)
#   - a pinned 16-colour ANSI palette, tuned for colour-vision deficiency
#
# WHY THE PALETTE IS NOW PINNED EXPLICITLY:
#   1. We only ever pinned foreground/background. The 16 ANSI colours were left to
#      each emulator's own default, so qterminal (Linux-console palette) and
#      xfce4-terminal (its own) rendered coloured output DIFFERENTLY - which quietly
#      broke the "identical screenshots" promise for every line our scripts colour.
#   2. The stock colours are bad on black: blue (#1818b2) sits at 1.81:1 contrast and
#      red (#b21818) at 3.04:1, both under the 4.5:1 readability floor for everyone,
#      and red falls to 2.19:1 for a protanope. Under deuteranopia the stock green
#      renders #a7952e - identical to the body text, so "[+] ok" stops being a colour.
#      Screenshots go into a PDF report, so this costs legibility with the judges too.
#   The palette below keeps every conventional hue but clears 5.6:1 on black under
#   normal, protan, deutan and tritan vision, with the four status colours held at
#   least dE00 25 apart (was 18.8). Success moves from pure green to mint: that is
#   the one deliberate change, and it is what buys the separation.
#
# Surgical: only the appearance keys below are touched; every other preference is
# left alone. Idempotent - safe to re-run. Each config is backed up once (*.cptcbak).
#
# NEEDS ROOT FOR THE QTERMINAL HALF. qtermwidget only reads colour schemes from
# /usr/share/qtermwidget*/color-schemes - not from the user's ~/.local/share - so the
# generated scheme has to be installed system-wide. Without root the script degrades
# to a built-in dark scheme rather than selecting one qterminal cannot load, because
# an unresolvable scheme silently yields a WHITE background (see install_qt_scheme).
# start.sh primes sudo before calling this; standalone, expect a password prompt.
#
# Usage:  bash terminal_uniform.sh
#
# IMPORTANT: qterminal rewrites its ENTIRE config file to its in-memory settings
# every time it exits. So any qterminal that was already open when we applied the
# uniform (e.g. the one you ran this from) will overwrite our edits back to its
# defaults on close - and logging out clobbers it for exactly this reason.
# To make the uniform stick regardless, we set qterminal.ini immutable (chattr +i)
# after writing it, so qterminal's on-exit save silently fails and our config stays.
# This needs root (start.sh already primes sudo); it degrades to a warning otherwise.
# To change qterminal settings later:  sudo chattr -i ~/.config/qterminal.org/qterminal.ini
# xfce4-terminal does NOT rewrite on exit, so it needs no lock - only NEW windows
# pick up the change.

# Body text / background. Unchanged from the original uniform - green-on-black is
# already safe (7.0-8.0:1 under every vision type), so only the accents move.
GREEN_FG="#18b218"
BLACK_BG="#000000"
FONT="FiraCode 10"

# The 16 ANSI colours, slots 0-15. Our scripts' status colours map like this:
#   [-] RED    \033[0;31m -> slot 1     [!] YELLOW \033[1;33m -> slot 11 (BOLD -> bright)
#   [+] GREEN  \033[0;32m -> slot 2     [*] BLUE   \033[0;34m -> slot 4
# Slot 11 - not slot 3 - is the warning colour, because 1;33 is bold. The bright
# variants (8-15) are tinted from the same hues so that a terminal which maps bold
# onto bright still lands on a safe colour. Slot 8 is intentionally dim: it is the
# conventional "comment/disabled" grey and carries no meaning in our output.
PALETTE=(
    "#000000"  # 0  black
    "#E06E85"  # 1  red      <- [-] error
    "#71F5E8"  # 2  green    <- [+] success  (mint, not pure green - see header)
    "#D6CB3A"  # 3  yellow
    "#5A9AFA"  # 4  blue     <- [*] info
    "#C77BE8"  # 5  magenta
    "#8ED8F0"  # 6  cyan
    "#C7D2C9"  # 7  white
    "#4E5A53"  # 8  bright black
    "#F08CA0"  # 9  bright red
    "#9CFFF5"  # 10 bright green
    "#F7EC48"  # 11 bright yellow <- [!] warning
    "#8FBEFF"  # 12 bright blue
    "#E0A8F5"  # 13 bright magenta
    "#B8ECFA"  # 14 bright cyan
    "#FFFFFF"  # 15 bright white
)

QT_SCHEME="CPTC"                       # name qterminal will reference

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

QT_INI="$USER_HOME/.config/qterminal.org/qterminal.ini"
XT_INI="$USER_HOME/.config/xfce4/terminal/terminalrc"

# --- set (or insert) key=value under a named [Section] of an INI-style file ---
# Key match is file-global (both configs keep each key in a single section), which
# mirrors the original qterminal-only version.
set_ini_key() {
    local f=$1 section=$2 k=$3 v=$4
    if grep -q "^${k}=" "$f"; then
        sed -i "s|^${k}=.*|${k}=${v}|" "$f"
    elif grep -q "^\[${section}\]" "$f"; then
        sed -i "/^\[${section}\]/a ${k}=${v}" "$f"
    else
        printf '[%s]\n%s=%s\n' "$section" "$k" "$v" >> "$f"
    fi
}

# --- ensure the config exists, back it up once, then apply all key=value pairs ---
apply_uniform() {
    local f=$1 section=$2; shift 2
    mkdir -p "$(dirname "$f")"
    if [ ! -f "$f" ]; then
        printf '[%s]\n' "$section" > "$f"
        echo "[*] No $(basename "$f") yet - created a fresh one."
    fi
    # Back up once, and only claim it when it actually happened: `cp -n` exits 0 when
    # it SKIPS an existing target, so the old `cp -n ... && echo "Backed up"` reported
    # a fresh backup on every re-run while leaving the original (possibly long stale)
    # .cptcbak in place.
    if [ -e "$f.cptcbak" ]; then
        echo "[*] Backup already exists, left as-is -> $f.cptcbak"
        echo "    (it is from the FIRST run, not the current file - delete it to re-take)"
    elif cp "$f" "$f.cptcbak"; then
        echo "[+] Backed up current config -> $f.cptcbak"
    fi
    local kv
    for kv in "$@"; do
        set_ini_key "$f" "$section" "${kv%%=*}" "${kv#*=}"
    done
    echo "[+] Applied uniform to $f:"
    printf '      %s\n' "$@"
}

# --- "#rrggbb" -> "r,g,b", the encoding qterminal colour schemes use ---
hex_to_rgb() {
    local h=${1#\#}
    printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

# --- render PALETTE as a qterminal/qtermwidget colour scheme file ---
# qterminal has no ini key for individual ANSI colours - it can only name a scheme
# file, so we generate one.
render_qt_scheme() {
    local out=$1 i
    {
        printf '[General]\nDescription=%s\nOpacity=1\nWallpaper=\n\n' "$QT_SCHEME"
        printf '[Background]\nColor=%s\n\n'        "$(hex_to_rgb "$BLACK_BG")"
        printf '[BackgroundIntense]\nColor=%s\n\n' "$(hex_to_rgb "$BLACK_BG")"
        printf '[Foreground]\nColor=%s\n\n'        "$(hex_to_rgb "$GREEN_FG")"
        printf '[ForegroundIntense]\nColor=%s\n\n' "$(hex_to_rgb "$GREEN_FG")"
        # Konsole/qtermwidget name the bright half "ColorNIntense", not Color8-15.
        for i in 0 1 2 3 4 5 6 7; do
            printf '[Color%d]\nColor=%s\n\n'        "$i" "$(hex_to_rgb "${PALETTE[$i]}")"
            printf '[Color%dIntense]\nColor=%s\n\n' "$i" "$(hex_to_rgb "${PALETTE[$((i+8))]}")"
        done
    } > "$out"
}

# --- install the scheme where qtermwidget will actually find it ---
#
# VERIFIED ON KALI 2026.2 (qterminal/qtermwidget 2.4.0, Qt6): qtermwidget searches
# ONLY the system dir - the hardcoded "/usr/share/qtermwidget6/color-schemes" is the
# sole colour-scheme path in libqtermwidget6.so. It does NOT read
# ~/.local/share/qtermwidget6/color-schemes.
#
# This matters more than it sounds: if colorScheme names a scheme qtermwidget cannot
# resolve, it does not keep the previous look - it falls back to its built-in default,
# which is a WHITE background with the stock ANSI palette. So an uninstallable scheme
# leaves the box worse off than never running this script. Hence: install to the
# system dir (needs root), and if that fails, do NOT point colorScheme at CPTC - fall
# back to a built-in dark scheme so the background at least stays black.
#
# Returns 0 if "$QT_SCHEME" is now resolvable by qtermwidget, 1 otherwise.
install_qt_scheme() {
    local tmp sysdirs=() d base installed=0
    tmp=$(mktemp) || return 1
    render_qt_scheme "$tmp"

    for d in /usr/share/qtermwidget*/color-schemes; do
        [ -d "$d" ] && sysdirs+=("$d")
    done

    if [ ${#sysdirs[@]} -eq 0 ]; then
        echo "[!] qtermwidget is not installed yet - no colour-scheme dir to install into."
        echo "    Re-run this script after all.sh has put the tools on."
        rm -f "$tmp"
        return 1
    fi

    for d in "${sysdirs[@]}"; do
        if sudo install -m 0644 "$tmp" "$d/$QT_SCHEME.colorscheme" 2>/dev/null; then
            echo "[+] Installed colour scheme -> $d/$QT_SCHEME.colorscheme"
            installed=1
        else
            echo "[!] Could not install into $d (needs root)."
        fi
        # Mirror into the per-user dir from the same source. qtermwidget 2.4.0 does
        # NOT read this - it is not load-bearing - but it costs nothing and is the
        # correct location if a later version ever honours XDG_DATA_HOME.
        base="$USER_HOME/.local/share/$(basename "${d%/color-schemes}")/color-schemes"
        mkdir -p "$base" && install -m 0644 "$tmp" "$base/$QT_SCHEME.colorscheme" 2>/dev/null
    done

    rm -f "$tmp"
    [ "$installed" -eq 1 ]
}

# --- pick a built-in dark scheme to fall back to if we cannot install ours ---
# Ordered best-first; all four ship with qtermwidget. Anything is better than the
# white default, so we take the first one that actually exists on this box.
pick_fallback_scheme() {
    local cand d
    for cand in GreenOnBlack WhiteOnBlack Kali-Dark Linux; do
        for d in /usr/share/qtermwidget*/color-schemes; do
            [ -f "$d/$cand.colorscheme" ] && { printf '%s' "$cand"; return 0; }
        done
    done
    return 1
}

# --- qterminal ([General] section, its own key names / value encodings) ---
# Unlock first so a previous run's immutable bit doesn't block our edits (no-op if
# not set / not root).
sudo chattr -i "$QT_INI" 2>/dev/null

# Only name CPTC in the ini if it is actually installed - see install_qt_scheme.
if install_qt_scheme; then
    QT_SCHEME_EFFECTIVE=$QT_SCHEME
else
    QT_SCHEME_EFFECTIVE=$(pick_fallback_scheme)
    if [ -n "$QT_SCHEME_EFFECTIVE" ]; then
        echo "[!] Could not install the CPTC scheme, so NOT selecting it: an unresolvable"
        echo "    scheme makes qterminal fall back to a WHITE background."
        echo "    Falling back to the built-in '$QT_SCHEME_EFFECTIVE' - black background,"
        echo "    but the stock ANSI palette, so colours will NOT match other operators."
        echo "    Re-run this with root available to get the real uniform."
    else
        echo "[!] Could not install the CPTC scheme and found no built-in dark scheme."
        echo "    Leaving colorScheme untouched rather than risking a white background."
    fi
fi

apply_uniform "$QT_INI" General \
    ${QT_SCHEME_EFFECTIVE:+"colorScheme=$QT_SCHEME_EFFECTIVE"} \
    "TerminalTransparency=0" \
    "TerminalBackgroundMode=0" \
    "fontFamily=FiraCode" \
    "fontSize=10"

# Lock it so no open/closing qterminal can overwrite it on exit (see header).
if sudo chattr +i "$QT_INI" 2>/dev/null; then
    echo "[+] Locked $QT_INI (immutable) - qterminal can no longer revert it."
    echo "    To edit qterminal settings later:  sudo chattr -i \"$QT_INI\""
else
    echo "[!] Could NOT lock $QT_INI (need root, or filesystem lacks chattr support)."
    echo "    Without the lock, apply this with ALL qterminal windows closed (from a"
    echo "    TTY/SSH) or an open qterminal will overwrite it again on exit."
fi

echo

# --- xfce4-terminal ([Configuration] section, explicit colours = same look) ---
# xfce4-terminal takes the whole palette on one semicolon-separated line.
XT_PALETTE=$(IFS=';'; printf '%s' "${PALETTE[*]}")

apply_uniform "$XT_INI" Configuration \
    "FontName=$FONT" \
    "ColorForeground=$GREEN_FG" \
    "ColorBackground=$BLACK_BG" \
    "ColorPalette=$XT_PALETTE" \
    "BackgroundMode=TERMINAL_BACKGROUND_SOLID"

# --- verify: prove the scheme qterminal will load actually resolves ---
# The failure this catches is silent and total (white background, stock palette), so
# it is worth the six lines. A named-but-missing scheme is the one outcome we cannot
# allow to pass unnoticed.
echo
selected=$(grep -m1 '^colorScheme=' "$QT_INI" 2>/dev/null | cut -d= -f2-)
if [ -z "$selected" ]; then
    echo "[!] VERIFY: no colorScheme set in $QT_INI - qterminal will use its default."
else
    found=""
    for d in /usr/share/qtermwidget*/color-schemes; do
        [ -f "$d/$selected.colorscheme" ] && found=$d/$selected.colorscheme && break
    done
    if [ -n "$found" ]; then
        echo "[+] VERIFY: colorScheme=$selected resolves -> $found"
        [ "$selected" = "$QT_SCHEME" ] \
            || echo "[!] NOTE: this is the FALLBACK scheme, not the CPTC uniform - colours will not match."
    else
        echo "[!] VERIFY FAILED: colorScheme=$selected is set but no such .colorscheme exists."
        echo "    qterminal will fall back to a WHITE background. Fix before screenshotting."
    fi
fi

# --- warn about any terminal that's open right now ---
running=()
pgrep -x qterminal      >/dev/null 2>&1 && running+=("qterminal")
pgrep -x xfce4-terminal >/dev/null 2>&1 && running+=("xfce4-terminal")
if [ ${#running[@]} -gt 0 ]; then
    echo
    echo "[!] Currently open: ${running[*]}"
    echo "    These windows still show the OLD look until you close them - just open a"
    echo "    NEW terminal to see the uniform. If qterminal.ini was locked above, those"
    echo "    open windows can no longer revert it on exit."
else
    echo
    echo "[*] Open a new terminal (qterminal or xfce4-terminal) to see the uniform."
fi
