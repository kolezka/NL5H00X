#!/bin/bash
# Root steps for the NL5H00X projector: install the sud daemon, its init
# service, and the su allow-list; optionally the hybrid su.
#
# Same four-function contract as lib/unlock.sh:
#
#   <step>_describe   one line of what it changes
#   <step>_state      applied | not-applied | blocked:<reason>
#   <step>_apply      make the change
#   <step>_revert     put it back
#
# Nothing is assumed to have worked: every apply is followed by reading the
# value back off the device. Steps are idempotent: re-running a finished step
# is a no-op.

[[ -n "${_ROOT_SH_LOADED:-}" ]] && return 0
_ROOT_SH_LOADED=1

# Built artifacts. Default: the repo's own root/ directory, where
# root/build.sh puts sud, su and sud.rc lives alongside the C sources.
ROOT_ARTIFACT_DIR="${ROOT_ARTIFACT_DIR:-$SCRIPT_DIR/../../root}"

# Device paths -- shared contract with the C side (root/sud.c, root/su.c).
# Changing any of these here without changing them there breaks the daemon.
SUD_BIN_PATH="/system/xbin/sud"
SU_HYBRID_PATH="/system/xbin/su"
SU_ORIG_PATH="/system/xbin/su_orig"
SU_NEW_PATH="/system/xbin/su_new"
SUD_RC_PATH="/system/etc/init/sud.rc"
SU_ALLOW_DIR="/data/adb"
SU_ALLOW_FILE="/data/adb/su-allow"
STAGING="/data/local/tmp"

# SELinux domain sud.rc asks init to transition the daemon into. Overridable
# because it only exists if this device's policy defines it -- see root/sud.rc.
SUD_SECLABEL="${SUD_SECLABEL:-u:r:su:s0}"

# Fixed order for --revert and the single-step menu. --apply-all filters this
# through apply_steps() so su_hybrid stays opt-in there.
ROOT_STEPS=(daemon_binary daemon_service allow_list su_hybrid)

apply_steps() {
    local s
    for s in "${ROOT_STEPS[@]}"; do
        [[ "$s" == "su_hybrid" && "${WITH_SU:-0}" != "1" ]] && continue
        printf '%s\n' "$s"
    done
}

# ---------------------------------------------------------------------------
# hashing: prefer sha256sum, fall back to md5sum. Whichever the device
# answers decides which algorithm the local side has to match.
# ---------------------------------------------------------------------------
remote_hash() {
    local path="$1" out digest
    out=$(adb_root_exec "sha256sum $path" 2>/dev/null)
    digest=$(awk '{print $1}' <<<"$out")
    if [[ "$digest" =~ ^[0-9a-f]{64}$ ]]; then
        echo "sha256:$digest"
        return 0
    fi
    out=$(adb_root_exec "md5sum $path" 2>/dev/null)
    digest=$(awk '{print $1}' <<<"$out")
    if [[ "$digest" =~ ^[0-9a-f]{32}$ ]]; then
        echo "md5:$digest"
        return 0
    fi
    return 1
}

local_hash() {
    local path="$1" algo="$2"
    if [[ "$algo" == "sha256" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$path" | awk '{print $1}'
        else
            shasum -a 256 "$path" | awk '{print $1}'
        fi
    else
        if command -v md5 >/dev/null 2>&1; then
            md5 -q "$path"
        else
            md5sum "$path" | awk '{print $1}'
        fi
    fi
}

# True if the device file's hash matches the local file's, using whichever
# algorithm the device actually answered.
device_matches_local() {
    local device_path="$1" local_path="$2" rh algo digest lh
    [[ -f "$local_path" ]] || return 1
    rh=$(remote_hash "$device_path") || return 1
    algo="${rh%%:*}"; digest="${rh#*:}"
    lh=$(local_hash "$local_path" "$algo")
    [[ -n "$lh" && "$lh" == "$digest" ]]
}

# True if two files ON THE DEVICE hash the same. Used where the comparison is
# su_orig vs. su rather than device vs. local artifact.
device_hashes_match() {
    local a="$1" b="$2" ha hb
    ha=$(remote_hash "$a") || return 1
    hb=$(remote_hash "$b") || return 1
    [[ "$ha" == "$hb" ]]
}

device_file_exists() {
    adb_root_exec "ls -d $1" >/dev/null 2>&1
}

sud_running() {
    adb_root_exec "pidof sud" 2>/dev/null | grep -qE '[0-9]'
}

# adb root itself runs through su. Any edit to the live su risks losing root
# entirely -- and if that happens, the next adb_root_exec failure reads exactly
# like "file absent", which would make a later step believe the very thing that
# broke root is clean. Call this right after every touch to $SU_HYBRID_PATH
# (the apply promote step, and revert) and stop the whole run outright if root
# is gone, rather than let the caller treat a false reading as truth.
verify_root_after_su_touch() {
    check_root_access && return 0
    print_error "adb root lost after touching $SU_HYBRID_PATH"
    print_error "Restore it from the permanent stock copy over UART: cp $SU_ORIG_PATH $SU_HYBRID_PATH && chmod 755 $SU_HYBRID_PATH (see ROOT.sh --repair)"
    exit 1
}

# Best-effort only: a reboot is what actually drops sud for good. This just
# stops a same-session check from seeing a daemon whose binary or service was
# just removed.
kill_sud_best_effort() {
    local pid; pid=$(adb_root_exec "pidof sud" 2>/dev/null | tr -d '\r\n ')
    if [[ -n "$pid" ]]; then
        adb_root_exec "kill $pid" >/dev/null 2>&1 || true
        print_warning "sud (pid $pid) killed best-effort -- a reboot is what fully drops the daemon"
    fi
}

# ---------------------------------------------------------------------------
# staged install: push locally, place as root, chmod/chown, verify by hash.
# Same pattern as launcher_present_apply / INSTALL_APP.sh's install_app.
# Caller is responsible for system_rw/system_ro around a /system target.
# ---------------------------------------------------------------------------
stage_and_install() {
    local local_path="$1" device_path="$2" mode="$3"
    local staged="$STAGING/$(basename "$device_path").$$"

    if ! adb push "$local_path" "$staged" >/dev/null 2>&1; then
        print_error "Could not stage $local_path to $staged"
        return 1
    fi

    adb_root_exec "mkdir -p $(dirname "$device_path")" >/dev/null || true
    adb_root_exec "cp $staged $device_path" >/dev/null || true
    adb_root_exec "chmod $mode $device_path" >/dev/null || true
    adb_root_exec "chown root:root $device_path" >/dev/null || true
    adb_root_exec "rm -f $staged" >/dev/null 2>&1 || true

    if ! device_matches_local "$device_path" "$local_path"; then
        print_error "$device_path does not match $local_path after install"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# step: daemon_binary
# ---------------------------------------------------------------------------
daemon_binary_artifact() { echo "$ROOT_ARTIFACT_DIR/sud"; }

daemon_binary_describe() {
    echo "Install the root daemon (sud) to $SUD_BIN_PATH"
}

daemon_binary_state() {
    local artifact; artifact=$(daemon_binary_artifact)
    [[ -f "$artifact" ]] || { echo "blocked:no $artifact - run root/build.sh first"; return; }
    device_file_exists "$SUD_BIN_PATH" || { echo not-applied; return; }
    device_matches_local "$SUD_BIN_PATH" "$artifact" && echo applied || echo not-applied
}

daemon_binary_apply() {
    local artifact; artifact=$(daemon_binary_artifact)
    [[ -f "$artifact" ]] || { print_error "No $artifact - run root/build.sh first"; return 1; }
    system_rw || return 1
    stage_and_install "$artifact" "$SUD_BIN_PATH" 755
    local rc=$?
    system_ro
    return $rc
}

daemon_binary_revert() {
    device_file_exists "$SUD_BIN_PATH" || return 0
    system_rw || return 1
    adb_root_exec "rm -rf $SUD_BIN_PATH" >/dev/null || true
    system_ro
    if device_file_exists "$SUD_BIN_PATH"; then
        print_error "Could not remove $SUD_BIN_PATH"
        return 1
    fi
    kill_sud_best_effort
    return 0
}

# ---------------------------------------------------------------------------
# step: daemon_service
# ---------------------------------------------------------------------------
daemon_service_template() { echo "$ROOT_ARTIFACT_DIR/sud.rc"; }

# root/sud.rc ships with seclabel u:r:su:s0. Substitute it for SUD_SECLABEL so
# an override takes without hand-editing the shipped template.
#
# Validated before it ever reaches a device: an empty or malformed seclabel
# (e.g. a bare --seclabel with its value swallowed by a typo) would render an
# init script whose seclabel line silently drops the value, or keeps whatever
# was last in the template -- either way installing something nobody asked for.
render_sud_rc() {
    local template="$1" out="$2"
    if [[ -z "$SUD_SECLABEL" ]]; then
        print_error "SUD_SECLABEL is empty"
        return 1
    fi
    if ! [[ "$SUD_SECLABEL" =~ ^[a-z0-9_]+:[a-z0-9_]+:[a-z0-9_]+:s[0-9]+$ ]]; then
        print_error "SUD_SECLABEL '$SUD_SECLABEL' is not a valid seclabel (expected user:role:type:sN)"
        return 1
    fi
    sed -E "s/^([[:space:]]*seclabel[[:space:]]+).*/\1$SUD_SECLABEL/" "$template" > "$out"
}

daemon_service_describe() {
    echo "Install the init service for sud at $SUD_RC_PATH (seclabel $SUD_SECLABEL)"
}

daemon_service_state() {
    local template; template=$(daemon_service_template)
    [[ -f "$template" ]] || { echo "blocked:no $template"; return; }
    device_file_exists "$SUD_RC_PATH" || { echo not-applied; return; }
    local rendered; rendered=$(mktemp)
    if ! render_sud_rc "$template" "$rendered"; then
        rm -f "$rendered"
        echo "blocked:invalid SUD_SECLABEL '$SUD_SECLABEL'"
        return
    fi
    if device_matches_local "$SUD_RC_PATH" "$rendered"; then
        rm -f "$rendered"
        echo applied
    else
        rm -f "$rendered"
        echo not-applied
    fi
}

daemon_service_apply() {
    local template; template=$(daemon_service_template)
    [[ -f "$template" ]] || { print_error "No $template"; return 1; }
    local rendered; rendered=$(mktemp)
    if ! render_sud_rc "$template" "$rendered"; then
        rm -f "$rendered"
        return 1
    fi
    system_rw || { rm -f "$rendered"; return 1; }
    stage_and_install "$rendered" "$SUD_RC_PATH" 644
    local rc=$?
    system_ro
    rm -f "$rendered"
    return $rc
}

daemon_service_revert() {
    device_file_exists "$SUD_RC_PATH" || return 0
    system_rw || return 1
    adb_root_exec "rm -rf $SUD_RC_PATH" >/dev/null || true
    system_ro
    if device_file_exists "$SUD_RC_PATH"; then
        print_error "Could not remove $SUD_RC_PATH"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# step: allow_list
# ---------------------------------------------------------------------------
allow_list_describe() {
    echo "Create the su allow-list at $SU_ALLOW_FILE (fail closed: empty means nobody)"
}

allow_list_state() {
    device_file_exists "$SU_ALLOW_DIR" || { echo not-applied; return; }
    device_file_exists "$SU_ALLOW_FILE" && echo applied || echo not-applied
}

allow_list_apply() {
    adb_root_exec "mkdir -p $SU_ALLOW_DIR" >/dev/null || true
    adb_root_exec "chmod 700 $SU_ALLOW_DIR" >/dev/null || true
    if ! device_file_exists "$SU_ALLOW_FILE"; then
        local empty; empty=$(mktemp)
        : > "$empty"
        if ! stage_and_install "$empty" "$SU_ALLOW_FILE" 600; then
            rm -f "$empty"
            return 1
        fi
        rm -f "$empty"
    fi
    device_file_exists "$SU_ALLOW_FILE"
}

allow_list_revert() {
    device_file_exists "$SU_ALLOW_FILE" || return 0
    adb_root_exec "rm -rf $SU_ALLOW_FILE" >/dev/null || true
    if device_file_exists "$SU_ALLOW_FILE"; then
        print_error "Could not remove $SU_ALLOW_FILE"
        return 1
    fi
    return 0
}

# Current allow-list content, one package per line.
allow_list_read() {
    adb_root_exec "cat $SU_ALLOW_FILE" 2>/dev/null
}

allow_list_write() {
    local content_file="$1"
    adb_root_exec "mkdir -p $SU_ALLOW_DIR" >/dev/null || true
    adb_root_exec "chmod 700 $SU_ALLOW_DIR" >/dev/null || true
    stage_and_install "$content_file" "$SU_ALLOW_FILE" 600
}

allow_list_add() {
    local pkg="$1" tmp rc
    tmp=$(mktemp)
    { allow_list_read; echo "$pkg"; } | grep -v '^[[:space:]]*$' | sort -u > "$tmp"
    allow_list_write "$tmp"
    rc=$?
    rm -f "$tmp"
    return $rc
}

allow_list_remove() {
    local pkg="$1" tmp rc
    tmp=$(mktemp)
    allow_list_read | grep -vx "$pkg" | grep -v '^[[:space:]]*$' > "$tmp" || true
    allow_list_write "$tmp"
    rc=$?
    rm -f "$tmp"
    return $rc
}

# ---------------------------------------------------------------------------
# step: su_hybrid (opt-in, --with-su)
#
# The live su is never touched until a hybrid binary has proven itself working
# under its OWN path, and su_orig is never deleted -- it is the permanent
# stock copy, and the only recovery path if the live su ever turns out broken.
#
#   1. Resolve stock su (command -v su); must be $SU_HYBRID_PATH or refuse.
#   2. Preserve the stock su as su_orig, if not already preserved, and verify
#      that copy by hash before trusting it.
#   3. Stage the hybrid artifact to $SU_NEW_PATH -- NOT the live su -- and
#      hash-verify it there.
#   4. Live-verify via $SU_NEW_PATH itself, with no reboot: this execs
#      su_orig unchanged for uid 0 (see root/su.c), so it exercises the
#      hybrid without the live su ever being at risk.
#   5. Only on that pass, promote: cp su_new over the live su, verify by
#      hash, remove su_new.
#
# adb root runs through su, so every touch to the live su is followed by
# verify_root_after_su_touch, which aborts the whole run outright if that
# touch cost us root -- never silently read as "file absent".
# ---------------------------------------------------------------------------
su_hybrid_artifact() { echo "$ROOT_ARTIFACT_DIR/su"; }

su_hybrid_describe() {
    echo "Install the hybrid su at $SU_HYBRID_PATH, keeping the stock su as $SU_ORIG_PATH"
}

# "applied" is purely su matching the hybrid artifact -- su_orig persisting
# (it always does, by design) has no bearing on this.
su_hybrid_state() {
    local artifact; artifact=$(su_hybrid_artifact)
    [[ -f "$artifact" ]] || { echo "blocked:no $artifact - run root/build.sh first"; return; }
    device_matches_local "$SU_HYBRID_PATH" "$artifact" && echo applied || echo not-applied
}

su_hybrid_apply() {
    local artifact; artifact=$(su_hybrid_artifact)
    [[ -f "$artifact" ]] || { print_error "No $artifact - run root/build.sh first"; return 1; }

    local stock; stock=$(adb_root_exec "command -v su" 2>/dev/null | tr -d '\r\n ')
    if [[ -z "$stock" ]]; then
        print_error "No su found on the device to preserve"
        return 1
    fi
    if [[ "$stock" != "$SU_HYBRID_PATH" ]]; then
        print_error "Stock su is at '$stock', not $SU_HYBRID_PATH - refusing (unexpected layout)"
        return 1
    fi

    system_rw || return 1

    if ! device_file_exists "$SU_ORIG_PATH"; then
        local stock_hash; stock_hash=$(remote_hash "$SU_HYBRID_PATH")
        if [[ -z "$stock_hash" ]]; then
            print_error "Could not hash the stock su at $SU_HYBRID_PATH before preserving it"
            system_ro
            return 1
        fi
        adb_root_exec "cp $SU_HYBRID_PATH $SU_ORIG_PATH" >/dev/null || true
        adb_root_exec "chmod 755 $SU_ORIG_PATH" >/dev/null || true
        adb_root_exec "chown root:root $SU_ORIG_PATH" >/dev/null || true
        local orig_hash; orig_hash=$(remote_hash "$SU_ORIG_PATH")
        if [[ -z "$orig_hash" || "$orig_hash" != "$stock_hash" ]]; then
            print_error "su_orig does not match the stock su it was copied from - removing it, not proceeding"
            adb_root_exec "rm -rf $SU_ORIG_PATH" >/dev/null || true
            system_ro
            return 1
        fi
    fi

    # Stage the hybrid at a NEW path. The live su is still untouched here.
    if ! stage_and_install "$artifact" "$SU_NEW_PATH" 755; then
        adb_root_exec "rm -rf $SU_NEW_PATH" >/dev/null || true
        system_ro
        return 1
    fi
    system_ro

    print_status "Live-verifying via $SU_NEW_PATH, with no reboot and the live su untouched"
    local out; out=$(adb shell "$SU_NEW_PATH 0 id" 2>/dev/null | tr -d '\r')
    if [[ "$out" != *"uid=0"* ]]; then
        print_error "$SU_NEW_PATH 0 id returned '$out', not uid=0 - the live su was never touched"
        system_rw || return 1
        adb_root_exec "rm -rf $SU_NEW_PATH" >/dev/null || true
        system_ro
        return 1
    fi
    print_success "$SU_NEW_PATH 0 id returns uid=0 - promoting it to $SU_HYBRID_PATH"

    system_rw || return 1
    adb_root_exec "cp $SU_NEW_PATH $SU_HYBRID_PATH" >/dev/null || true
    adb_root_exec "chmod 755 $SU_HYBRID_PATH" >/dev/null || true
    adb_root_exec "chown root:root $SU_HYBRID_PATH" >/dev/null || true
    adb_root_exec "rm -rf $SU_NEW_PATH" >/dev/null || true
    system_ro

    verify_root_after_su_touch    # exits outright if this cost us adb root

    if ! device_matches_local "$SU_HYBRID_PATH" "$artifact"; then
        print_error "$SU_HYBRID_PATH does not match $artifact after promoting the hybrid"
        return 1
    fi
    print_success "$SU_HYBRID_PATH matches the hybrid artifact"
    return 0
}

su_hybrid_revert() {
    device_file_exists "$SU_ORIG_PATH" || return 0
    system_rw || return 1
    adb_root_exec "cp $SU_ORIG_PATH $SU_HYBRID_PATH" >/dev/null || true
    adb_root_exec "chmod 755 $SU_HYBRID_PATH" >/dev/null || true
    adb_root_exec "chown root:root $SU_HYBRID_PATH" >/dev/null || true
    system_ro

    verify_root_after_su_touch    # exits outright if this cost us adb root

    # su_orig is the permanent safety copy: it is never deleted. Success here
    # is su now matching su_orig by hash, not su_orig's absence.
    if ! device_hashes_match "$SU_HYBRID_PATH" "$SU_ORIG_PATH"; then
        print_error "$SU_HYBRID_PATH does not match $SU_ORIG_PATH after restoring it"
        return 1
    fi
    kill_sud_best_effort
    return 0
}
