#!/usr/bin/env bash
#
# configure-davfs.sh — Configure davfs2 for mailbox.org WebDAV
#
# Provides:  configure_davfs
# Requires:  MOUNT_POINT  WEBDAV_URL  MAILBOX_EMAIL  MAILBOX_PASSWORD
#            CURRENT_USER
#

configure_davfs() {
    configure_davfs_conf
    configure_davfs_secrets
    configure_fstab
    configure_davfs_suid
    configure_davfs_group
}

# ---------------------------------------------------------------------------

configure_davfs_conf() {
    local conf_file="/etc/davfs2/davfs2.conf"

    info "Writing ${conf_file}..."

    # Back up the original once
    if [[ -f "${conf_file}" ]] && [[ ! -f "${conf_file}.orig" ]]; then
        sudo cp "${conf_file}" "${conf_file}.orig"
        info "Original backed up to ${conf_file}.orig"
    fi

    sudo tee "${conf_file}" > /dev/null << 'DAVFS2CONF'
# /etc/davfs2/davfs2.conf
# Configured by mailbox-drive-assistant for mailbox.org
# Original file backed up as davfs2.conf.orig
#
# Settings not listed here use davfs2 built-in defaults.

if_match_bug    1
use_locks       0
cache_size      1
table_size      4096
delay_upload    1
gui_optimize    1
buf_size        64
DAVFS2CONF

    ok "davfs2.conf written"
}

# ---------------------------------------------------------------------------

configure_davfs_secrets() {
    local secrets_file="/etc/davfs2/secrets"

    info "Storing credentials in ${secrets_file}..."

    # Ensure file exists
    if [[ ! -f "${secrets_file}" ]]; then
        sudo touch "${secrets_file}"
    fi

    # Remove any previous entry for this mount point (idempotent)
    if sudo grep -q "^${MOUNT_POINT} " "${secrets_file}" 2>/dev/null; then
        sudo sed -i "\|^${MOUNT_POINT} |d" "${secrets_file}"
        info "Replaced existing entry for ${MOUNT_POINT}"
    fi

    # Append credentials — password quoted for safety with special characters
    printf '%s %s "%s"\n' \
        "${MOUNT_POINT}" "${MAILBOX_EMAIL}" "${MAILBOX_PASSWORD}" \
        | sudo tee -a "${secrets_file}" > /dev/null

    sudo chmod 600 "${secrets_file}"
    sudo chown root:root "${secrets_file}"

    ok "Credentials stored securely"
}

# ---------------------------------------------------------------------------

configure_fstab() {
    local fstab_entry="${WEBDAV_URL} ${MOUNT_POINT} davfs noauto,user,rw 0 0"

    info "Checking /etc/fstab..."

    if grep -q "${MOUNT_POINT}.*davfs" /etc/fstab 2>/dev/null; then
        ok "fstab entry for ${MOUNT_POINT} already exists"
        # Reload even if entry existed — it may have been added in a previous
        # incomplete run and systemd might not know about it yet.
        sudo systemctl daemon-reload
        return 0
    fi

    sudo cp /etc/fstab /etc/fstab.bak
    info "fstab backed up to /etc/fstab.bak"

    echo "${fstab_entry}" | sudo tee -a /etc/fstab > /dev/null

    # Notify systemd about the fstab change so mount works immediately
    sudo systemctl daemon-reload

    ok "fstab entry added for ${MOUNT_POINT}"
}

# ---------------------------------------------------------------------------

configure_davfs_suid() {
    info "Enabling SUID for mount.davfs (allows non-root mount)..."

    echo "davfs2 davfs2/suid_file boolean true" | sudo debconf-set-selections
    sudo dpkg-reconfigure -f noninteractive davfs2

    ok "SUID bit set on mount.davfs"
}

# ---------------------------------------------------------------------------

configure_davfs_group() {
    info "Checking davfs2 group membership..."

    if id -nG "${CURRENT_USER}" | grep -qw "davfs2"; then
        ok "User '${CURRENT_USER}' is already in the davfs2 group"
        return 0
    fi

    sudo usermod -aG davfs2 "${CURRENT_USER}"

    ok "User '${CURRENT_USER}' added to davfs2 group (effective after next login)"
}