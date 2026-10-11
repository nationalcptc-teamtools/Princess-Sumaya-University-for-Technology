#!/bin/bash
#
# jvis_logsync.sh -- start / stop / status of the jVision log-sync daemon.
#
# Wraps jvis_logsync.py (shipped in the jVision repo). Prompts for jVision
# credentials, spawns the Python daemon in the background under nohup, tracks
# it via a PID file, and rotates its stdout/stderr into ~/.jvis_logsync.log.
#
# Usage:
#   ./jvis_logsync.sh start [-i IP] [-p PORT] [-u USER]   (prompts for missing)
#   ./jvis_logsync.sh stop
#   ./jvis_logsync.sh status
#   ./jvis_logsync.sh log                                 (tail -f the log)
#
# One-shot for the day:
#   ./jvis_logsync.sh start -i 192.168.50.3 -u mustafa

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sudo-safe home, same approach as lib.sh/start.sh: the readable logs this daemon
# tails live in the OPERATOR's home, so if this is ever launched under sudo we must
# not go looking in /root for them. Derived from the script's own path.
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
USER_HOME="${USER_HOME:-$(cptc_user_home)}"
export USER_HOME          # jvis_logsync.py reads this too

PID_FILE="$USER_HOME/.jvis_logsync.pid"
LOG_FILE="$USER_HOME/.jvis_logsync.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# The Python daemon lives in the jVision repo. Set JVIS_PY=/full/path if yours
# is somewhere the auto-discover doesn't cover.
find_script() {
    if [ -n "${JVIS_PY:-}" ] && [ -f "${JVIS_PY:-}" ]; then
        echo "$JVIS_PY"; return 0
    fi
    for p in \
        "$SCRIPT_DIR/jvis_logsync.py" \
        "$USER_HOME/cptc/jvesion/Princess-Sumaya-University-for-Technology/jVision/jvis_logsync.py" \
        "$USER_HOME/jVision/jvis_logsync.py" \
        "$USER_HOME/cptc/jVision/jvis_logsync.py" \
        "/opt/jVision/jvis_logsync.py"; do
        [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

is_running() {
    [ -f "$PID_FILE" ] || return 1
    local pid; pid=$(cat "$PID_FILE" 2>/dev/null || true)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

cmd_start() {
    local ip="" port="" user=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -i) ip="$2"; shift 2 ;;
            -p) port="$2"; shift 2 ;;
            -u) user="$2"; shift 2 ;;
            *)  echo -e "${RED}unknown arg: $1${NC}" >&2; exit 2 ;;
        esac
    done

    if is_running; then
        echo -e "${YELLOW}already running (pid $(cat "$PID_FILE"))${NC}"
        exit 0
    fi

    local script; script=$(find_script) || {
        echo -e "${RED}jvis_logsync.py not found${NC}" >&2
        echo "Looked in:" >&2
        echo "  \$JVIS_PY env var" >&2
        echo "  $SCRIPT_DIR/  (next to this launcher)" >&2
        echo "  ~/cptc/jvesion/Princess-Sumaya-University-for-Technology/jVision/" >&2
        echo "  ~/jVision/, ~/cptc/jVision/, /opt/jVision/" >&2
        echo "" >&2
        echo "Fix: either download jvis_logsync.py into $SCRIPT_DIR, or" >&2
        echo "     export JVIS_PY=/full/path/to/jvis_logsync.py before running." >&2
        exit 3
    }

    # Prompt for anything missing. Password is always read silently.
    [ -z "$ip" ]   && { read -rp "jVision server IP: " ip; }
    [ -z "$user" ] && { read -rp "jVision username: "  user; }
    read -rsp "jVision password: " pass; echo

    [ -z "$port" ] && port=7777

    echo -e "${BLUE}[*]${NC} starting daemon (script: $script)"
    # Password via env only -- avoids leaking to `ps aux` or shell history.
    JVIS_PASS="$pass" nohup python3 "$script" \
        -i "$ip" -p "$port" -u "$user" \
        >>"$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}[+]${NC} started (pid $pid). Log: $LOG_FILE"
    else
        echo -e "${RED}[-]${NC} daemon died immediately; tail $LOG_FILE for reason"
        rm -f "$PID_FILE"
        tail -n 20 "$LOG_FILE" >&2 || true
        exit 4
    fi
}

cmd_stop() {
    if ! is_running; then
        echo -e "${YELLOW}not running${NC}"
        rm -f "$PID_FILE"
        exit 0
    fi
    local pid; pid=$(cat "$PID_FILE")
    kill -TERM "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${YELLOW}forcing kill${NC}"
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    echo -e "${GREEN}[+]${NC} stopped"
}

cmd_status() {
    if is_running; then
        echo -e "${GREEN}running${NC} (pid $(cat "$PID_FILE"), log $LOG_FILE)"
    else
        echo -e "${YELLOW}not running${NC}"
    fi
}

cmd_log() {
    [ -f "$LOG_FILE" ] || { echo "no log yet at $LOG_FILE"; exit 1; }
    tail -f "$LOG_FILE"
}

CMD="${1:-help}"; shift || true
case "$CMD" in
    start)  cmd_start "$@" ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    log)    cmd_log ;;
    *)
        cat <<HELP
jvis_logsync.sh -- background log-sync daemon for jVision.

  start [-i IP] [-p PORT] [-u USER]   start (prompts for anything missing +
                                      always prompts for password)
  stop                                stop cleanly (SIGTERM, then SIGKILL)
  status                              running / not running
  log                                 tail -f the daemon log

Environment: set JVIS_PY=/full/path/to/jvis_logsync.py to override the auto-lookup.
HELP
        ;;
esac
