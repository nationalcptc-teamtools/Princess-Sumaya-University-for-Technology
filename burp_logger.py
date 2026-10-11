# -*- coding: utf-8 -*-
# CPTC Engagement Logger - Burp Suite extension (Jython 2.7)
#
# PEP 263 encoding declaration above is REQUIRED. Jython 2.7 refuses to parse a
# file containing any non-ASCII byte unless one of the first two lines matches
# `coding[:=]\s*([-\w.]+)`. A `⚠️` emoji in a comment further down triggered:
#   SyntaxError: Non-ASCII character in file ... but no encoding declared
# so Burp failed to load the extension on an operator's box. Keep this header.
#
# Companion to command_logging.sh. Appends one line per manual-testing request
# to ~/.burp_history_readable so we have an attribution-grade artifact of what
# actually left the box during the engagement -- if the target's system breaks
# and the client asks "prove what you did at time T", this file is the answer.
#
# Format (single line per request; grep-friendly):
#   <YYYY-MM-DD HH:MM:SS> [<TOOL>] <status> <METHOD> <URL> [CT=<content-type>] [BODY=<body>]
# Session markers on load/unload:
#   <YYYY-MM-DD HH:MM:SS> --- Burp session started ---
#   <YYYY-MM-DD HH:MM:SS> --- Burp session ended ---
#
# Tools logged: Repeater, Intruder, Scanner (Scanner is Pro-only; no-op on
# Community). Proxy is off by default (flip LOG_PROXY_IN_SCOPE to log in-scope
# Proxy traffic too).
#
# Body logging is gated to methods that carry payload data:
#   POST/PUT/PATCH -- always logged (BODY=<empty> if server-side was empty)
#   DELETE          -- logged only if body is non-empty
#   GET/HEAD/OPTIONS/... -- never logged
# Bodies are capped at BODY_MAX bytes and truncated with a marker. Binary bodies
# (null bytes or >30% non-printable) are summarised as <binary N bytes>.
#
# Redaction (applied to URL query string and body content):
#   FULL redact ([REDACTED]):
#     password, passwd, passphrase, pwd, secret, JSON "password":"..." etc.
#     basic-auth password in URL (user:PASS@host)
#   Prefix-keep first 3 chars (auth-granting but useful to identify type):
#     token, access_token, refresh_token, api_key, apikey, bearer,
#     bare JWTs anywhere in body (eyJ...)
#   Prefix-keep first 2 chars (identifying, needed for client correlation):
#     session, sessionid, PHPSESSID, JSESSIONID
#   NO redaction:
#     usernames -- kept as-is, deliberately. The log exists so the client can
#     answer "which account touched this at time T"; a masked username defeats
#     the only question it is there to answer. Secrets must never be in the
#     file, identities are the point of the file.
#
# Hashes and Kerberos tickets are FULLY redacted (they were prefix-kept before):
# an NTLM hash is a credential outright -- pass-the-hash needs nothing else --
# so keeping any of it is keeping the secret.

from __future__ import print_function

from burp import IBurpExtender, IHttpListener, IExtensionStateListener
import os
import re
import time
import threading

LOG_FILE = os.path.expanduser("~/.burp_history_readable")

# Flip to True to also log Proxy traffic (in-scope only).
LOG_PROXY_IN_SCOPE = False

# Per-request body cap in bytes. Bodies longer than this get truncated with a
# marker in the log; full body still lives in Burp's session.
BODY_MAX = 8 * 1024

BODY_METHODS_ALWAYS      = set(["POST", "PUT", "PATCH"])
BODY_METHODS_IF_NONEMPTY = set(["DELETE"])


# --------------------------------------------------------------------------
# Redaction
# --------------------------------------------------------------------------

# ⚠️ KEEP IN STEP WITH command_logging.sh's always-on 'password|passwd|...' rule.
# These two redactors are the two halves of one evidence layer, and they had
# already diverged: this list was missing a bare `pass`, so a login form posting
# `user=admin&pass=hunter2` was logged in clear while the shell side redacted the
# same key. `pass` is one of the commonest field names in a web form, and web is
# the deepest sub-team. Added 2026-10-05, along with pw/passcode/credential.
# `redaction_test.sh` now exercises BOTH redactors against one shared battery of
# cases, so the next divergence fails a test instead of reaching the client.
# Longest alternatives first (the `=` anchor makes order harmless, but it reads
# clearer and is robust if the anchor is ever relaxed).
_FULL_KEYS    = (r"passphrase|passcode|passwd|password|credentials|credential"
                 r"|secret|pwd|pass|pw")
_TOKEN_KEYS   = r"token|access_token|refresh_token|api_key|apikey|bearer"
_SESSION_KEYS = r"session|sessionid|phpsessid|jsessionid"
_HASH_KEYS    = r"hash(?:es)?|nthash(?:es)?|lmhash|nthashes|aeskey|ntlm"
_TICKET_KEYS  = r"ticket|krbcred|kirbi|ccache|tgt|tgs"

# key = value  in URL query, form body, JS-object-ish, config-file-ish text.
# Value forms recognized: "double-quoted"  |  'single-quoted'  |  bareword-no-ws.
# Whitespace tolerated around '=' so `password = "hunter2"` matches too.
_VAL = r'(?:"[^"]*"|\'[^\']*\'|[^&\s#]+)'
_URL_FULL    = re.compile(r"(?i)\b(" + _FULL_KEYS    + r")\s*=\s*(" + _VAL + r")")
_URL_TOKEN   = re.compile(r"(?i)\b(" + _TOKEN_KEYS   + r")\s*=\s*(" + _VAL + r")")
_URL_SESSION = re.compile(r"(?i)\b(" + _SESSION_KEYS + r")\s*=\s*(" + _VAL + r")")
_URL_HASH    = re.compile(r"(?i)\b(" + _HASH_KEYS    + r")\s*=\s*(" + _VAL + r")")
_URL_TICKET  = re.compile(r"(?i)\b(" + _TICKET_KEYS  + r")\s*=\s*(" + _VAL + r")")

# JSON:  "key":"value"   (best-effort -- doesn't handle escaped quotes in value)
_JSON_FULL    = re.compile(r'(?i)("(?:' + _FULL_KEYS    + r')"\s*:\s*)"([^"]*)"')
_JSON_TOKEN   = re.compile(r'(?i)("(?:' + _TOKEN_KEYS   + r')"\s*:\s*)"([^"]*)"')
_JSON_SESSION = re.compile(r'(?i)("(?:' + _SESSION_KEYS + r')"\s*:\s*)"([^"]*)"')
_JSON_HASH    = re.compile(r'(?i)("(?:' + _HASH_KEYS    + r')"\s*:\s*)"([^"]*)"')
_JSON_TICKET  = re.compile(r'(?i)("(?:' + _TICKET_KEYS  + r')"\s*:\s*)"([^"]*)"')

# Basic-auth user:pass@host embedded in a URL: keep the username, hide the pass
_URL_BASIC = re.compile(r"://([^:/@\s]+):([^@\s]+)@")

# Bare JWT tokens anywhere in a body (base64url header.payload.signature).
# `eyJ` is the base64 encoding of `{"` and is JWT's near-universal prefix.
_BARE_JWT = re.compile(r"\beyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")


def _keep_prefix(n, val):
    if len(val) <= n:
        return val
    return val[:n] + "[REDACTED]"


def _unquote(v):
    # Strip a matching pair of surrounding single or double quotes.
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        return v[1:-1]
    return v


def _redact_url(url):
    url = _URL_FULL.sub(   lambda m: m.group(1) + "=[REDACTED]",                                    url)
    url = _URL_TOKEN.sub(  lambda m: m.group(1) + "=" + _keep_prefix(3, _unquote(m.group(2))),      url)
    url = _URL_SESSION.sub(lambda m: m.group(1) + "=" + _keep_prefix(2, _unquote(m.group(2))),      url)
    url = _URL_HASH.sub(   lambda m: m.group(1) + "=[REDACTED]",                                    url)
    url = _URL_TICKET.sub( lambda m: m.group(1) + "=[REDACTED]",                                    url)
    # username kept, password dropped
    url = _URL_BASIC.sub(  lambda m: "://" + m.group(1) + ":[REDACTED]@",                           url)
    return url


def _redact_body(body):
    # form / key=value forms (also fires inside urlencoded and some multipart)
    body = _URL_FULL.sub(   lambda m: m.group(1) + "=[REDACTED]",                                     body)
    body = _URL_TOKEN.sub(  lambda m: m.group(1) + "=" + _keep_prefix(3, _unquote(m.group(2))),       body)
    body = _URL_SESSION.sub(lambda m: m.group(1) + "=" + _keep_prefix(2, _unquote(m.group(2))),       body)
    body = _URL_HASH.sub(   lambda m: m.group(1) + "=[REDACTED]",                                      body)
    body = _URL_TICKET.sub( lambda m: m.group(1) + "=[REDACTED]",                                      body)
    # JSON forms
    body = _JSON_FULL.sub(   lambda m: m.group(1) + '"[REDACTED]"',                          body)
    body = _JSON_TOKEN.sub(  lambda m: m.group(1) + '"' + _keep_prefix(3, m.group(2)) + '"', body)
    body = _JSON_SESSION.sub(lambda m: m.group(1) + '"' + _keep_prefix(2, m.group(2)) + '"', body)
    body = _JSON_HASH.sub(   lambda m: m.group(1) + '"[REDACTED]"',                          body)
    body = _JSON_TICKET.sub( lambda m: m.group(1) + '"[REDACTED]"',                          body)
    # bare JWTs anywhere (unlabeled Bearer tokens embedded in payloads, etc.)
    body = _BARE_JWT.sub(lambda m: _keep_prefix(3, m.group(0)), body)
    return body


def _escape_control(s):
    # Newlines/CRs would break the one-line-per-request invariant grep relies on.
    return s.replace(u"\r", u"\\r").replace(u"\n", u"\\n").replace(u"\t", u"\\t")


# --------------------------------------------------------------------------
# Body handling
# --------------------------------------------------------------------------

def _looks_binary(byte_arr, offset, end):
    # Scan up to first 2KB of the body region. Null byte -> definitely binary.
    # Otherwise, treat as binary if >30% of scanned bytes are non-printable.
    scan_end = min(end, offset + 2048)
    scanned = scan_end - offset
    if scanned <= 0:
        return False
    non_printable = 0
    for i in range(offset, scan_end):
        b = byte_arr[i] & 0xFF                        # java byte -> unsigned int
        if b == 0:
            return True
        if b < 32 and b not in (9, 10, 13):           # allow TAB/LF/CR
            non_printable += 1
        elif b == 127:
            non_printable += 1
    return non_printable * 10 > scanned * 3


def _extract_content_type(headers):
    for h in headers:
        # headers is a Java List<String> of raw header lines
        if h.lower().startswith("content-type:"):
            return h.split(":", 1)[1].strip()
    return None


# --------------------------------------------------------------------------
# Extension
# --------------------------------------------------------------------------

class BurpExtender(IBurpExtender, IHttpListener, IExtensionStateListener):

    def registerExtenderCallbacks(self, callbacks):
        self._callbacks = callbacks
        self._helpers = callbacks.getHelpers()
        self._lock = threading.Lock()

        self._tool_names = {
            callbacks.TOOL_REPEATER: "REPEATER",
            callbacks.TOOL_INTRUDER: "INTRUDER",
            callbacks.TOOL_SCANNER:  "SCANNER",
            callbacks.TOOL_PROXY:    "PROXY",
        }
        self._log_tools = set([
            callbacks.TOOL_REPEATER,
            callbacks.TOOL_INTRUDER,
            callbacks.TOOL_SCANNER,   # no-op on Community
        ])
        self._proxy_tool = callbacks.TOOL_PROXY

        callbacks.setExtensionName("CPTC Engagement Logger")
        callbacks.registerHttpListener(self)
        callbacks.registerExtensionStateListener(self)

        # Ensure log file exists and is owner-only.
        try:
            if not os.path.exists(LOG_FILE):
                open(LOG_FILE, "a").close()
            os.chmod(LOG_FILE, 0o600)
        except Exception as e:
            print("[!] burp_logger: could not prepare " + LOG_FILE + ": " + str(e))

        self._write_line("--- Burp session started ---")

        print("[+] CPTC Engagement Logger loaded")
        print("    log file : " + LOG_FILE)
        proxy_note = ", Proxy (in-scope)" if LOG_PROXY_IN_SCOPE else ""
        print("    tools    : Repeater, Intruder, Scanner" + proxy_note)

    def extensionUnloaded(self):
        try:
            self._write_line("--- Burp session ended ---")
        except Exception:
            pass

    # -- writing ----------------------------------------------------------

    def _write_line(self, payload):
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        line = "%s %s\n" % (ts, payload)
        with self._lock:
            with open(LOG_FILE, "a") as f:
                f.write(line)

    # -- listener ---------------------------------------------------------

    def processHttpMessage(self, toolFlag, messageIsRequest, messageInfo):
        # Log on the response leg so we have a status code in hand.
        if messageIsRequest:
            return

        if toolFlag in self._log_tools:
            need_scope_check = False
        elif toolFlag == self._proxy_tool and LOG_PROXY_IN_SCOPE:
            need_scope_check = True
        else:
            return

        try:
            req = self._helpers.analyzeRequest(messageInfo)
            url_obj = req.getUrl()
            if need_scope_check and not self._callbacks.isInScope(url_obj):
                return

            method = req.getMethod()
            url_str = _redact_url(str(url_obj))
            tool = self._tool_names.get(toolFlag, "UNKNOWN")

            resp = messageInfo.getResponse()
            status = 0 if resp is None else self._helpers.analyzeResponse(resp).getStatusCode()

            ct = _extract_content_type(req.getHeaders())

            # Body extraction (only for methods that carry one)
            body_repr = None
            if method in BODY_METHODS_ALWAYS or method in BODY_METHODS_IF_NONEMPTY:
                full = messageInfo.getRequest()
                offset = req.getBodyOffset()
                body_len = len(full) - offset
                if body_len > 0:
                    if _looks_binary(full, offset, offset + body_len):
                        body_repr = "<binary %d bytes>" % body_len
                    else:
                        clip_end = offset + min(body_len, BODY_MAX)
                        text = self._helpers.bytesToString(full[offset:clip_end])
                        text = _redact_body(text)
                        text = _escape_control(text)
                        if body_len > BODY_MAX:
                            text += "...[truncated %d more bytes]" % (body_len - BODY_MAX)
                        body_repr = text
                elif method in BODY_METHODS_ALWAYS:
                    body_repr = "<empty>"

            parts = ["[" + tool + "]", str(status), method, url_str]
            if ct is not None:
                parts.append("CT=" + ct)
            if body_repr is not None:
                parts.append("BODY=" + body_repr)
            self._write_line(" ".join(parts))
        except Exception as e:
            print("[!] burp_logger: " + str(e))
