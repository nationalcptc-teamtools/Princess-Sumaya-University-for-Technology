#!/bin/bash
# ad.sh - COMPATIBILITY WRAPPER. The AD build now lives inside all.sh.
#
# WHY THIS FILE STILL EXISTS RATHER THAN BEING DELETED.
# ad.sh and all.sh were always run back to back, on the same box, sourcing the
# same lib.sh. Keeping them apart bought nothing and cost a duplicated ~80-line
# verification helper block that drifted between the two copies, two apt lists
# with five packages in both, two sudo keepalives, two dropzone creations, two
# APT-failure summaries and two pin summaries. They are one script now.
#
# The name stays because it is in muscle memory and in the printed on-site
# checklist, and engagement morning is the worst possible time to discover that a
# command you have typed all season no longer exists. So this forwards to the
# equivalent flag instead of failing.
#
#   bash ad.sh        ->  bash all.sh --ad-only
#
# Anything you used to pass to ad.sh (it took no arguments) still works, and any
# arguments given here are handed through.
#
# ⚠️ If you are building a box from scratch, you do NOT need this. Run
#    bash all.sh  -  it installs the AD tooling along with everything else.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
echo -e "${YELLOW}[!]${NC} ad.sh has been merged into all.sh."
echo -e "${BLUE}[*]${NC} Running: bash \"$SCRIPT_DIR/all.sh\" --ad-only $*"
echo -e "${BLUE}[*]${NC} For a fresh box, run all.sh with no flags - it does everything."
echo

exec bash "$SCRIPT_DIR/all.sh" --ad-only "$@"
