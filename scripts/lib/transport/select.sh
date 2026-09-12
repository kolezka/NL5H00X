#!/bin/bash
# layer: transport
# requires:

[ -n "${PT_TRANSPORT_SELECT_SH:-}" ] && return 0
PT_TRANSPORT_SELECT_SH=1

transport_init() {
    case "${PT_TRANSPORT:-live}" in
        fake)
            [[ -n "${PT_ADB_BIN:-}" ]] || {
                printf 'transport: fake needs PT_ADB_BIN\n' >&2
                return 2
            }
            [[ "$PT_ADB_BIN" == /* && -f "$PT_ADB_BIN" && -x "$PT_ADB_BIN" ]] || {
                printf 'transport: PT_ADB_BIN must be absolute and executable\n' >&2
                return 2
            }
            [[ "$PT_ADB_BIN" == "${PT_FAKE_ADB_CANONICAL:-}" ]] || {
                printf 'transport: fake mode accepts only the canonical fake\n' >&2
                return 2
            }
            ;;
        live)
            # An explicitly empty path is invalid too, not permission to use PATH.
            if [[ "${PT_ADB_BIN+x}" == x ]]; then
                [[ "$PT_ADB_BIN" == /* && -f "$PT_ADB_BIN" && -x "$PT_ADB_BIN" ]] || {
                    printf 'transport: explicit PT_ADB_BIN invalid; refusing\n' >&2
                    return 2
                }
            else
                PT_ADB_BIN=$(command -v adb 2>/dev/null) || {
                    printf 'transport: adb not on PATH\n' >&2
                    return 2
                }
                [[ "$PT_ADB_BIN" == /* && -f "$PT_ADB_BIN" && -x "$PT_ADB_BIN" ]] || {
                    printf 'transport: PATH must select an absolute executable file\n' >&2
                    return 2
                }
            fi
            ;;
        *)
            printf 'transport: unknown PT_TRANSPORT\n' >&2
            return 2
            ;;
    esac
    return 0
}

transport_selected_bin() {
    transport_init || return 2
    printf '%s\n' "$PT_ADB_BIN"
}
