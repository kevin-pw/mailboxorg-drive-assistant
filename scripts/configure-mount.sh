#!/usr/bin/env bash
#
# configure-mount.sh — Create directories, perform a test mount, detect display name
#
# Provides:  configure_mount
# Requires:  MOUNT_POINT  LOCAL_DIR  CURRENT_USER  CURRENT_GROUP  WEBDAV_URL
#
# Sets:      MAILBOX_DISPLAY_NAME (auto-detected from drive contents)
#            MAILBOX_DISPLAY_NAME_CANDIDATES (array, if multiple dirs found)
#

configure_mount() {
    create_mount_point
    create_local_dir
    test_mount
}

# ---------------------------------------------------------------------------

create_mount_point() {
    info "Setting up mount point at ${MOUNT_POINT}..."

    if [[ ! -d "${MOUNT_POINT}" ]]; then
        sudo mkdir -p "${MOUNT_POINT}"
        ok "Created ${MOUNT_POINT}"
    else
        ok "Mount point already exists: ${MOUNT_POINT}"
    fi

    sudo chown "${CURRENT_USER}:${CURRENT_GROUP}" "${MOUNT_POINT}"
    ok "Ownership set to ${CURRENT_USER}:${CURRENT_GROUP}"
}

# ---------------------------------------------------------------------------

create_local_dir() {
    info "Setting up local directory at ${LOCAL_DIR}..."

    if [[ ! -d "${LOCAL_DIR}" ]]; then
        mkdir -p "${LOCAL_DIR}"
        ok "Created ${LOCAL_DIR}"
    else
        ok "Local directory already exists: ${LOCAL_DIR}"
    fi
}

# ---------------------------------------------------------------------------

detect_display_name() {
    info "Detecting mailbox display name from drive contents..."

    # Directories to ignore when scanning the drive root
    local -a ignore_dirs=("lost+found")

    local dirs=()
    while IFS= read -r entry; do
        [[ -z "${entry}" ]] && continue

        # Skip ignored directories
        local skip=false
        for ignored in "${ignore_dirs[@]}"; do
            if [[ "${entry}" == "${ignored}" ]]; then
                skip=true
                break
            fi
        done
        [[ "${skip}" == true ]] && continue

        dirs+=("${entry}")
    done < <(find "${MOUNT_POINT}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null)

    if [[ ${#dirs[@]} -eq 1 ]]; then
        MAILBOX_DISPLAY_NAME="${dirs[0]}"
        ok "Auto-detected display name: ${MAILBOX_DISPLAY_NAME}"
    elif [[ ${#dirs[@]} -gt 1 ]]; then
        MAILBOX_DISPLAY_NAME_CANDIDATES=("${dirs[@]}")
        info "Multiple directories found in drive root:"
        for i in "${!dirs[@]}"; do
            info "  $((i+1)). ${dirs[$i]}"
        done
    else
        info "No directories found in drive root."
    fi
}

# ---------------------------------------------------------------------------
# mount_as_user — Mount the drive as the current user via the davfs2 group
#
# Uses `sg davfs2` to activate the group membership that was added via
# `usermod -aG` without requiring a logout/login cycle.
# Falls back to `sudo mount` if sg fails.
#
# Returns 0 on success, 1 on failure.
# ---------------------------------------------------------------------------

mount_as_user() {
    # Preferred: mount as the user with davfs2 group activated.
    # This ensures mounted files are owned by the user, not root.
    if sg davfs2 -c "mount '${MOUNT_POINT}'" 2>/dev/null; then
        return 0
    fi

    # Fallback: sudo mount (files may be root-owned)
    warn "User mount failed; falling back to sudo mount..."
    if sudo mount "${MOUNT_POINT}" 2>/dev/null; then
        warn "Mounted with sudo — write permissions may be restricted."
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------

test_mount() {
    info "Testing WebDAV mount..."

    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        ok "Drive is already mounted at ${MOUNT_POINT}"
        detect_display_name
        return 0
    fi

    # Mount as user so that permissions are correct from the start.
    if mount_as_user; then
        ok "Mount test successful — drive is accessible"

        info "Drive contents:"
        ls "${MOUNT_POINT}" 2>/dev/null | head -10 || true

        detect_display_name

        # Unmount after detection — Phase 7 will mount again for actual use
        sudo umount "${MOUNT_POINT}" 2>/dev/null \
            || sg davfs2 -c "umount '${MOUNT_POINT}'" 2>/dev/null \
            || true
        info "Test mount unmounted (will be remounted in final phase)"
    else
        warn "Mount test failed. Possible causes:"
        warn "  • Incorrect email or app password"
        warn "  • Network connectivity issue"
        warn "  • davfs2 group membership not yet active"
        warn ""
        warn "You can test manually after setup:"
        warn "  sg davfs2 -c \"mount '${MOUNT_POINT}'\""
    fi
}