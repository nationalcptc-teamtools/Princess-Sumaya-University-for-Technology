#!/bin/bash
# pins.sh - manage the artifact pin manifest in lib.sh.
#
# The manifest ships with sha256 values of "TBD" because a hash you have not
# actually computed is worse than no hash at all - it looks like verification
# while verifying nothing. This script computes the real ones.
#
# DO THIS ON A TRUSTED NETWORK, during a rehearsal, not on engagement day:
#   bash pins.sh --show      # what is pinned and what is not
#   bash pins.sh --record    # download everything, print the real sha256 lines
#   bash pins.sh --write     # same, but edit lib.sh in place (backup kept)
#   bash pins.sh --verify    # re-download and compare against the manifest
#   bash pins.sh --audit     # check what is INSTALLED ON THIS BOX (no network)
#
# --verify and --audit answer different questions. --verify asks "did upstream
# move?". --audit asks "is this box actually built from the manifest?" - it
# re-hashes the files ~/pins.lock says landed here. Run --audit on arrival and
# after any smol-all.sh rebuild.
#
# --record/--write/--verify take optional artifact names to narrow the run:
#   bash pins.sh --write mimikatz pstools sharphound_ce
# Use that rather than a bare --write when you only changed a few entries; a bare
# run re-downloads Android Studio's 1.5 GB along with everything else.
#
# --verify is the drift check: run it the week before the event. A mismatch on
# something we pinned means upstream moved a release asset under us; a mismatch
# on something marked 'latest'/'master' is expected and is the argument for
# pinning it.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh" || { echo "cannot source lib.sh"; exit 1; }

MODE=${1:---show}
[ $# -gt 0 ] && shift
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Any remaining arguments narrow the run to those artifacts:
#   bash pins.sh --record mimikatz pstools sharphound_ce
# Without this, --record/--verify download EVERY manifest entry, which means
# pulling Android Studio's 1.5 GB to re-hash a 40 KB PowerShell script. Named
# artifacts are validated against the manifest so a typo fails loudly instead of
# silently hashing nothing.
if [ $# -gt 0 ]; then
    for n in "$@"; do
        if [ -z "${PIN_URL[$n]:-}" ]; then
            print_error "no manifest entry named '$n'"
            print_status "known: $(printf '%s ' $(printf '%s\n' "${!PIN_URL[@]}" | sort))"
            exit 1
        fi
    done
    names=$(printf '%s\n' "$@" | sort)
    print_status "Limited to $# artifact(s): $*"
else
    names=$(printf '%s\n' "${!PIN_URL[@]}" | sort)
fi

case $MODE in
--show)
    printf '%-18s %-24s %s\n' "ARTIFACT" "VERSION" "SHA256"
    printf '%-18s %-24s %s\n' "--------" "-------" "------"
    for n in $names; do
        printf '%-18s %-24s %s\n' "$n" "${PIN_VER[$n]}" "${PIN_SHA[$n]}"
    done
    echo
    unpinned=0; unverified=0
    for n in $names; do
        case "${PIN_VER[$n]}" in latest|master|main) unpinned=$((unpinned+1)) ;; esac
        [ "${PIN_SHA[$n]}" = "TBD" ] && unverified=$((unverified+1))
    done
    print_status "$unpinned of $(echo "$names" | wc -w) artifacts track a moving target"
    print_status "$unverified of $(echo "$names" | wc -w) artifacts have no verified sha256"
    ;;

--record|--write)
    print_status "Downloading every manifest artifact to compute real hashes..."
    OUT="$TMP/lines"; : > "$OUT"
    fail=0
    for n in $names; do
        if curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 "${PIN_URL[$n]}" -o "$TMP/$n"; then
            sha=$(sha256sum "$TMP/$n" | cut -d' ' -f1)
            printf 'PIN_SHA[%s]="%s"\n' "$n" "$sha" >> "$OUT"
            print_success "$n  ${sha:0:16}...  ($(stat -c %s "$TMP/$n") bytes)"
        else
            print_error "$n  DOWNLOAD FAILED - leaving as TBD"
            fail=$((fail+1))
        fi
    done
    echo
    if [ "$MODE" = "--record" ]; then
        print_status "Paste these into lib.sh (or re-run with --write):"
        echo; cat "$OUT"
    else
        # Absolute, to match the sed below. Was relative, so running this from any
        # other directory backed up the wrong file (or nothing) while still editing
        # the real lib.sh - a backup that silently is not one.
        cp "$SCRIPT_DIR/lib.sh" "$SCRIPT_DIR/lib.sh.pins-bak-$(date +%s)"
        wrote=0; missed=()
        while IFS= read -r line; do
            key=${line%%]*}; key=${key#PIN_SHA[}
            sha=${line#*\"}; sha=${sha%\"}
            # Replace ONLY this key's sha assignment, wherever it sits on its line,
            # and leave URL/VER untouched.
            #
            # THIS USED TO BE ANCHORED WITH ^PIN_SHA\[ AND THEREFORE NEVER WORKED.
            # Almost every entry in lib.sh is laid out as
            #     PIN_VER[name]="v1.0";   PIN_SHA[name]="TBD"
            # i.e. PIN_SHA is mid-line, so the anchored pattern matched nothing. The
            # loop then "succeeded" on every artifact and changed not one byte, and
            # the script printed "lib.sh updated" regardless. Every hash in the
            # manifest stayed TBD while REHEARSAL.md told people this was the way to
            # fill them in - a verification step that verified nothing, which is the
            # exact failure the TBD convention exists to prevent.
            # Hence also the post-check below: never report a write we did not make.
            sed -i "s|PIN_SHA\[$key\]=\"[^\"]*\"|PIN_SHA[$key]=\"$sha\"|" "$SCRIPT_DIR/lib.sh"
            if grep -q "PIN_SHA\[$key\]=\"$sha\"" "$SCRIPT_DIR/lib.sh"; then
                wrote=$((wrote+1))
            else
                missed+=("$key")
            fi
        done < "$OUT"
        if [ "$wrote" -gt 0 ]; then
            print_success "lib.sh updated - $wrote hash(es) written (backup: lib.sh.pins-bak-*)"
            print_warning "Commit this. A pinned hash only helps if everyone builds from it."
        fi
        if [ ${#missed[@]} -gt 0 ]; then
            print_error "FAILED to write ${#missed[@]} hash(es): ${missed[*]}"
            print_error "  Those entries were not found in lib.sh in the expected form."
            print_error "  Expected:  PIN_SHA[<name>]=\"<value>\"   - fix the entry, re-run."
            exit 1
        fi
    fi
    [ "$fail" -gt 0 ] && print_warning "$fail artifact(s) could not be downloaded"
    ;;

--verify)
    print_status "Re-downloading and comparing against the manifest..."
    drift=0; skipped=0
    for n in $names; do
        if [ "${PIN_SHA[$n]}" = "TBD" ]; then
            print_warning "$n has no recorded hash - skipped (version: ${PIN_VER[$n]})"
            skipped=$((skipped+1)); continue
        fi
        if ! curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 "${PIN_URL[$n]}" -o "$TMP/$n"; then
            print_error "$n download failed"; drift=$((drift+1)); continue
        fi
        sha=$(sha256sum "$TMP/$n" | cut -d' ' -f1)
        if [ "$sha" = "${PIN_SHA[$n]}" ]; then
            print_success "$n unchanged"
        else
            print_error "$n CHANGED since it was pinned"
            print_error "   manifest: ${PIN_SHA[$n]}"
            print_error "   upstream: $sha"
            drift=$((drift+1))
        fi
    done
    echo
    if [ "$drift" -eq 0 ]; then
        print_success "No drift on any pinned artifact ($skipped unpinned, skipped)"
    else
        print_error "$drift artifact(s) drifted - investigate before the event"
        exit 1
    fi
    ;;

--audit)
    # THE QUESTION --verify CANNOT ANSWER.
    # --verify re-downloads and compares UPSTREAM against the manifest: it tells
    # you whether a release moved under us. It says nothing about the box you are
    # standing on. --audit compares WHAT IS ACTUALLY INSTALLED HERE against the
    # manifest, using the paths ~/pins.lock recorded as each artifact landed.
    #
    # Run it: on arrival, after a smol-all.sh rebuild, and on both boxes during a
    # rehearsal. It needs no network.
    if [ ! -f "$PINS_LOCK" ]; then
        print_error "no $PINS_LOCK on this box - nothing has been installed by all.sh/ad.sh yet"
        exit 1
    fi
    print_status "Auditing what is installed on THIS box against the manifest..."
    print_status "  (source: $PINS_LOCK - no network used)"
    echo
    okc=0; badc=0; gone=0; skip=0
    declare -A seen_path
    # Last entry wins: if an artifact was re-fetched later, that is the one on
    # disk now. Rows for things with no manifest entry (compiled Go binaries) are
    # skipped - there is nothing to compare them against.
    while IFS=$'\t' read -r _ts name _ver _sha path; do
        [ -n "${name:-}" ] || continue
        [ -n "${PIN_URL[$name]:-}" ] || continue
        seen_path[$name]=${path:--}
    done < "$PINS_LOCK"

    for n in $names; do
        p=${seen_path[$n]:-}
        if [ -z "$p" ]; then
            print_warning "$n  never recorded on this box (not installed, or installed before paths were logged)"
            skip=$((skip+1)); continue
        fi
        if [ "$p" = "-" ]; then
            print_status "$n  no single file to re-hash (clone or compiled binary) - skipped"
            skip=$((skip+1)); continue
        fi
        if [ ! -e "$p" ]; then
            print_error "$n  RECORDED BUT GONE: $p"
            gone=$((gone+1)); continue
        fi
        if [ -d "$p" ]; then
            print_status "$n  is a directory - skipped (use git to check a clone)"
            skip=$((skip+1)); continue
        fi
        want=${PIN_SHA[$n]}
        got=$(sha256sum "$p" 2>/dev/null | cut -d' ' -f1)
        if [ "$want" = "TBD" ]; then
            print_warning "$n  on disk but the manifest has no hash to check it against"
            skip=$((skip+1))
        elif [ "$got" = "$want" ]; then
            print_success "$n  matches the pin"
            okc=$((okc+1))
        else
            print_error "$n  DOES NOT MATCH THE PIN"
            print_error "    expected ${want:0:16}...  got ${got:0:16}..."
            print_error "    $p"
            badc=$((badc+1))
        fi
    done
    echo
    print_status "$okc match · $badc mismatched · $gone missing · $skip not checkable"
    if [ "$badc" -gt 0 ] || [ "$gone" -gt 0 ]; then
        print_error "This box is NOT built from the manifest. Delete the offending files and re-run"
        print_error "  the installer, or explain the difference before anyone relies on this box."
        exit 1
    fi
    print_success "Everything checkable on this box matches the pinned manifest."
    ;;

-h|--help) sed -n '2,28p' "$0" ;;
*) print_error "unknown mode: $MODE (try --help)"; exit 1 ;;
esac
