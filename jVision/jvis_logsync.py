#!/usr/bin/env python3
"""
jVision log sync -- runs on each operator's box during the engagement.

Tails ~/.zsh_history_readable and ~/.burp_history_readable, batches new lines
every N seconds, and pushes them (over an authenticated session cookie) to the
jVision server. On the server side they show up in the Logs tab, attributed to
the jVision user this script logs in as.

Why we ship this separately from jvisionclient.py: jvisionclient.py is a
one-shot scan tool; this is a long-running daemon that starts once at the
start of the day and runs until you stop it.
"""

import argparse
import getpass
import json
import os
import signal
import sys
import time
from datetime import datetime, timezone

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


SOURCES = {
    "zsh":  os.path.expanduser("~/.zsh_history_readable"),
    "burp": os.path.expanduser("~/.burp_history_readable"),
}

STATE_FILE = os.path.expanduser("~/.jvis_logsync_state.json")

# Both burp_logger.py and command_logging.sh prefix every line with a local
# timestamp in this shape. Parsing it back lets the server correlate events
# across operators even if their clocks are ~seconds apart.
TS_LEN = len("YYYY-MM-DD HH:MM:SS")


def log(msg):
    print("[{}] {}".format(datetime.now().strftime("%H:%M:%S"), msg), flush=True)


def load_state():
    if not os.path.exists(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(state):
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_FILE)


def parse_line_ts(line):
    # Returns ISO-8601 UTC string or None. Both log producers emit local-time
    # prefixes; assume they're UTC since the CPTC VDI images are typically
    # provisioned in UTC. If yours aren't, adjust here.
    if len(line) < TS_LEN:
        return None
    try:
        dt = datetime.strptime(line[:TS_LEN], "%Y-%m-%d %H:%M:%S")
        return dt.replace(tzinfo=timezone.utc).isoformat()
    except ValueError:
        return None


def read_new_lines(path, offset):
    # Returns (new_lines, new_offset). Handles rotation by detecting shrink
    # (someone truncated or rotated the file) and starting over from 0.
    try:
        size = os.path.getsize(path)
    except OSError:
        return [], offset

    if size < offset:
        log("{} shrunk ({} -> {}), assuming rotation; resetting offset".format(
            path, offset, size))
        offset = 0
    if size == offset:
        return [], offset

    with open(path, "rb") as f:
        f.seek(offset)
        chunk = f.read()
        new_offset = f.tell()

    # If the file doesn't end on a newline, hold back the trailing partial
    # line -- we'll pick it up on the next tick when it's complete.
    text = chunk.decode("utf-8", errors="replace")
    if not text.endswith("\n"):
        last_nl = text.rfind("\n")
        if last_nl == -1:
            return [], offset  # no complete line yet
        held_back = len(text) - (last_nl + 1)
        text = text[:last_nl + 1]
        new_offset -= held_back

    lines = [l for l in text.splitlines() if l.strip()]
    return lines, new_offset


def build_entries(lines, source):
    entries = []
    for line in lines:
        ts = parse_line_ts(line)
        entry = {
            "Source": source,
            "Line": line,
        }
        if ts:
            entry["Timestamp"] = ts
        entries.append(entry)
    return entries


class SyncClient:
    def __init__(self, base_url, username, password, batch_size=1000):
        self.base_url = base_url.rstrip("/")
        self.username = username
        self.password = password
        self.batch_size = batch_size
        self.session = requests.Session()
        self.session.verify = False

    def login(self):
        r = self.session.post(
            "{}/Auth/Login".format(self.base_url),
            json={"UserName": self.username, "Password": self.password,
                  "RememberMe": True},
            timeout=10,
        )
        if r.status_code != 200:
            raise RuntimeError("login failed ({}): {}".format(
                r.status_code, r.text[:200]))
        log("logged in as {}".format(self.username))

    def push(self, entries):
        # Server ignores/overrides the Operator field to whatever the cookie
        # says, so we don't bother setting it here.
        for i in range(0, len(entries), self.batch_size):
            batch = entries[i:i + self.batch_size]
            r = self.session.post(
                "{}/logs".format(self.base_url),
                json=batch, timeout=30,
            )
            if r.status_code == 401:
                log("session expired, re-authenticating")
                self.login()
                r = self.session.post(
                    "{}/logs".format(self.base_url),
                    json=batch, timeout=30,
                )
            if r.status_code != 200:
                raise RuntimeError("push failed ({}): {}".format(
                    r.status_code, r.text[:200]))


def main():
    ap = argparse.ArgumentParser(
        description="Sync ~/.zsh_history_readable and ~/.burp_history_readable to jVision.")
    ap.add_argument("-i", dest="server_ip", required=True,
                    help="jVision server IP")
    ap.add_argument("-p", dest="server_port", type=int, default=7777,
                    help="jVision server port (default: 7777)")
    ap.add_argument("-u", dest="username", required=True,
                    help="jVision username")
    ap.add_argument("-P", dest="password", default=None,
                    help="jVision password (prompts if omitted; prefer JVIS_PASS "
                         "env var so it doesn't show up in ps)")
    ap.add_argument("--interval", type=int, default=30,
                    help="seconds between sync ticks (default: 30)")
    ap.add_argument("--from-start", action="store_true",
                    help="ignore saved offsets; upload everything from the "
                         "beginning of each file (use once at engagement start "
                         "if you already have accumulated history)")
    args = ap.parse_args()

    password = os.environ.get("JVIS_PASS") or args.password \
        or getpass.getpass("jVision password: ")

    base_url = "http://{}:{}".format(args.server_ip, args.server_port)
    client = SyncClient(base_url, args.username, password)

    try:
        client.login()
    except Exception as e:
        log("fatal: {}".format(e))
        sys.exit(1)

    state = {} if args.from_start else load_state()
    stop = {"flag": False}

    def handle_sigint(_signum, _frame):
        log("caught SIGINT, saving state and exiting")
        save_state(state)
        stop["flag"] = True

    signal.signal(signal.SIGINT, handle_sigint)
    signal.signal(signal.SIGTERM, handle_sigint)

    log("watching: " + ", ".join(SOURCES.values()))
    log("interval: {}s   server: {}".format(args.interval, base_url))

    while not stop["flag"]:
        total = 0
        for source, path in SOURCES.items():
            if not os.path.exists(path):
                continue
            offset = state.get(source, {}).get("offset", 0)
            lines, new_offset = read_new_lines(path, offset)
            if not lines:
                state.setdefault(source, {})["offset"] = new_offset
                continue
            entries = build_entries(lines, source)
            try:
                client.push(entries)
            except Exception as e:
                log("push error for {}: {} -- will retry next tick".format(source, e))
                continue
            state.setdefault(source, {})["offset"] = new_offset
            total += len(entries)
        if total:
            log("pushed {} line(s)".format(total))
            save_state(state)
        for _ in range(args.interval):
            if stop["flag"]:
                break
            time.sleep(1)

    save_state(state)


if __name__ == "__main__":
    main()
