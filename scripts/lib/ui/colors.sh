#!/bin/bash
# layer: ui
# requires: nothing
#
# The single definition of the terminal color constants. Everything that needs
# a color sources this file; nothing else declares RED, GREEN, YELLOW, BLUE,
# CYAN, PURPLE, BOLD or NC. common.sh sources this file and must not re-declare
# them: they are readonly, so a second declaration is a fatal error, not a
# harmless overwrite.
#
# The include guard runs before the assignments for the same reason. Sourcing
# this file twice in one shell must be a no-op, and it only can be if the
# readonly lines never run a second time.

[ -n "${PT_UI_COLORS_SH:-}" ] && return 0
PT_UI_COLORS_SH=1

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'
