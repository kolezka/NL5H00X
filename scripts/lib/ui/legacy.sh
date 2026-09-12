#!/bin/bash
# layer: ui
# requires: ui render, ui colors
#
# The old presentation names, kept so existing scripts and the suites keep
# working while they migrate. A workflow that only needs to print something
# sources this file instead of the whole facade.
#
# Stream split, unchanged from common.sh: print_status, print_success and
# print_step stay on stdout, print_warning and print_error stay on stderr.
# Callers rely on both halves, so neither moves here.
#
# Compatibility runs one way. Nothing in this file calls a log_* function: the
# new writers are all on stderr, and routing an old stdout name through one
# would silently change where its output lands.

# shellcheck source-path=SCRIPTDIR

[ -n "${PT_UI_LEGACY_SH:-}" ] && return 0
PT_UI_LEGACY_SH=1

# shellcheck source=colors.sh
source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
# shellcheck source=render.sh
source "$(dirname "${BASH_SOURCE[0]}")/render.sh"

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }

print_header()  { render_header "$@"; }
print_section() { render_section "$@"; }
human_size()    { render_size "$@"; }

# Confirm action with user
# Usage: confirm "Are you sure?" && do_something
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"

    local yn_hint="y/N"
    [[ "$default" == "y" ]] && yn_hint="Y/n"

    read -r -p "$prompt ($yn_hint): " response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy]$ ]]
}

# Wait for user to press enter
pause() {
    local msg="${1:-Press Enter to continue...}"
    read -r -p "$msg"
}
