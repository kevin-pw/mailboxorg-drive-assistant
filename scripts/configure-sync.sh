#!/usr/bin/env bash
#
# configure-sync.sh — Render FreeFileSync batch and RealTimeSync config
#
# Provides:  configure_sync
# Requires:  SCRIPT_DIR  FREEFILESYNC_INSTALL_DIR  MOUNT_POINT  LOCAL_DIR
#            MAILBOX_DISPLAY_NAME  LOCAL_SYNC_DELAY_SECONDS
#

configure_sync() {
    if [[ ! -d "${FREEFILESYNC_INSTALL_DIR}" ]]; then
        warn "FreeFileSync install directory not found: ${FREEFILESYNC_INSTALL_DIR}"
        warn "Skipping sync configuration. Configure manually after installing FreeFileSync."
        return 1
    fi

    render_batch_config
    render_real_config
}

# ---------------------------------------------------------------------------
# sed_escape_replacement — Escape characters special in sed replacement
#   Handles: & \ / | (using | as delimiter)
# ---------------------------------------------------------------------------

sed_escape_replacement() {
    printf '%s' "$1" | sed 's/[&\\/|]/\\&/g'
}

# ---------------------------------------------------------------------------
# render_template — Generic template renderer
#
# Usage: render_template <template_file> <output_file>
#
# Replaces all __PLACEHOLDER__ tokens with their corresponding values.
# ---------------------------------------------------------------------------

render_template() {
    local template_file="$1"
    local output_file="$2"

    if [[ ! -f "${template_file}" ]]; then
        err "Template not found: ${template_file}"
        return 1
    fi

    sed \
        -e "s|__MOUNT_POINT__|$(sed_escape_replacement "${MOUNT_POINT}")|g" \
        -e "s|__LOCAL_DIR__|$(sed_escape_replacement "${LOCAL_DIR}")|g" \
        -e "s|__DISPLAY_NAME__|$(sed_escape_replacement "${MAILBOX_DISPLAY_NAME}")|g" \
        -e "s|__FREEFILESYNC_INSTALL_DIR__|$(sed_escape_replacement "${FREEFILESYNC_INSTALL_DIR}")|g" \
        -e "s|__DELAY_SECONDS__|$(sed_escape_replacement "${LOCAL_SYNC_DELAY_SECONDS}")|g" \
        "${template_file}" > "${output_file}"
}

# ---------------------------------------------------------------------------

render_batch_config() {
    local template="${SCRIPT_DIR}/templates/BatchRun.ffs_batch"
    local output="${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_batch"

    info "Rendering FreeFileSync batch config..."

    if [[ -f "${output}" ]]; then
        local backup="${output}.bak.$(date +%Y%m%d%H%M%S)"
        cp "${output}" "${backup}"
        info "Existing batch config backed up to: $(basename "${backup}")"
    fi

    render_template "${template}" "${output}"
    ok "Created: ${output}"
}

# ---------------------------------------------------------------------------

render_real_config() {
    local template="${SCRIPT_DIR}/templates/BatchRun.ffs_real"
    local output="${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_real"

    info "Rendering RealTimeSync config..."

    if [[ -f "${output}" ]]; then
        local backup="${output}.bak.$(date +%Y%m%d%H%M%S)"
        cp "${output}" "${backup}"
        info "Existing RealTimeSync config backed up to: $(basename "${backup}")"
    fi

    render_template "${template}" "${output}"
    ok "Created: ${output}"
}