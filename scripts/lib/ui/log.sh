#!/bin/bash
# layer: ui
# requires: ui colors
#
# Diagnostics for the operator. Every writer here goes to stderr, including the
# progress-shaped ones, because helpers elsewhere return their payload on stdout
# and are called as out=$(helper ...). A diagnostic written to stdout is
# captured into the caller's variable and never reaches the person watching.
#
# The bracketed prefixes are the ones common.sh has always printed, so operators
# and the test suites keep reading the same strings.

# shellcheck source-path=SCRIPTDIR

[ -n "${PT_UI_LOG_SH:-}" ] && return 0
PT_UI_LOG_SH=1

# shellcheck source=colors.sh
source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

log_info()  { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step()  { echo -e "${PURPLE}[STEP]${NC} $1" >&2; }
