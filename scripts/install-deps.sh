#!/usr/bin/env bash
#
# install-deps.sh — Install davfs2 and FreeFileSync
#
# Provides:  install_dependencies
# Requires:  FREEFILESYNC_VERSION  FREEFILESYNC_INSTALL_DIR  HOME
#

install_dependencies() {
    install_davfs2
    install_freefilesync
}

# ---------------------------------------------------------------------------

install_davfs2() {
    if dpkg-query -W -f='${Status}' davfs2 2>/dev/null \
            | grep -q "install ok installed"; then
        ok "davfs2 is already installed"
        return 0
    fi

    info "Installing davfs2..."

    # Preseed debconf so the installer does not prompt about SUID
    echo "davfs2 davfs2/suid_file boolean false" | sudo debconf-set-selections

    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y davfs2; then
        info "Retrying after apt-get update..."
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y davfs2
    fi

    ok "davfs2 installed"
}

# ---------------------------------------------------------------------------
# post_install_freefilesync — Set up symlinks and verify installation
#
# The FreeFileSync installer creates:
#   ~/.local/bin/FreeFileSync  → <install_dir>/FreeFileSync
#   ~/.local/bin/freefilesync  → <install_dir>/FreeFileSync
#
# When these are missing we create them ourselves.
# ---------------------------------------------------------------------------

post_install_freefilesync() {
    local install_dir="$1"
    local bin_dir="${HOME}/.local/bin"

    mkdir -p "${bin_dir}"

    # Symlink: ~/.local/bin/FreeFileSync
    if [[ ! -e "${bin_dir}/FreeFileSync" ]]; then
        ln -sf "${install_dir}/FreeFileSync" "${bin_dir}/FreeFileSync"
        ok "Symlink created: ${bin_dir}/FreeFileSync"
    else
        info "Symlink already exists: ${bin_dir}/FreeFileSync"
    fi

    # Symlink: ~/.local/bin/freefilesync (lowercase alias)
    if [[ ! -e "${bin_dir}/freefilesync" ]]; then
        ln -sf "${install_dir}/FreeFileSync" "${bin_dir}/freefilesync"
        ok "Symlink created: ${bin_dir}/freefilesync"
    else
        info "Symlink already exists: ${bin_dir}/freefilesync"
    fi

    # Verify expected directory structure
    local expected_items=("FreeFileSync" "RealTimeSync" "Bin" "Resources")
    local missing=()
    for item in "${expected_items[@]}"; do
        if [[ ! -e "${install_dir}/${item}" ]]; then
            missing+=("${item}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "Installation structure verified (FreeFileSync, RealTimeSync, Bin/, Resources/)"
    else
        warn "Some expected items not found in ${install_dir}:"
        for item in "${missing[@]}"; do
            warn "  - ${item}"
        done
        warn "FreeFileSync may still work, but the installation may be incomplete."
    fi
}

# ---------------------------------------------------------------------------
# run_interactive_install — Launch the installer with step-by-step guidance
# ---------------------------------------------------------------------------

run_interactive_install() {
    local run_file="$1"
    local target_dir="$2"

    echo ""
    info "╔══════════════════════════════════════════════════════════════════╗"
    info "║           FreeFileSync Interactive Installer                     ║"
    info "║                                                                  ║"
    info "║  The installer will open. Follow these steps IN ORDER:           ║"
    info "║                                                                  ║"
    info "║  Step 1:  Press  y  to accept the license agreement              ║"
    info "║                                                                  ║"
    info "║  Step 2:  Press  1  to set 'Install for all users' to NO         ║"
    info "║                                                                  ║"
    info "║  Step 3:  Press  2  to change the installation directory         ║"
    info "║           Then paste the following path and press Enter:         ║"
    info "║                                                                  ║"
    info "║           ${target_dir}"
    info "║                                                                  ║"
    info "║  Step 4:  Press  3  to set 'Create desktop shortcuts' to NO      ║"
    info "║                                                                  ║"
    info "║  Step 5:  Press  Enter  to begin installation                    ║"
    info "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    info "TIP: Copy the path above before pressing Enter below."
    info "     You can paste it in the installer with Ctrl+Shift+V."
    echo ""

    # Copy path to clipboard if xclip or xsel is available
    if command -v xclip &>/dev/null; then
        echo -n "${target_dir}" | xclip -selection clipboard 2>/dev/null && \
            ok "Installation path copied to clipboard (Ctrl+Shift+V to paste)"
    elif command -v xsel &>/dev/null; then
        echo -n "${target_dir}" | xsel --clipboard 2>/dev/null && \
            ok "Installation path copied to clipboard (Ctrl+Shift+V to paste)"
    fi

    read -rp "Press Enter to launch the FreeFileSync installer..."
    echo ""

    # Run the installer
    "${run_file}" || true

    # Check if installation succeeded at expected path
    if [[ -x "${target_dir}/FreeFileSync" ]]; then
        ok "FreeFileSync installed successfully"
        return 0
    fi

    # Search common locations in case the user chose a different path
    echo ""
    warn "FreeFileSync not found at ${target_dir}"
    info "Searching common installation locations..."

    local search_paths=(
        "/opt/FreeFileSync"
        "${HOME}/FreeFileSync"
        "${HOME}/programs/FreeFileSync"
        "${HOME}/Programs/FreeFileSync"
        "/usr/local/FreeFileSync"
        "/usr/share/FreeFileSync"
    )

    for sp in "${search_paths[@]}"; do
        if [[ -x "${sp}/FreeFileSync" && "${sp}" != "${target_dir}" ]]; then
            info "Found FreeFileSync at ${sp}"
            read -rp "Copy to ${target_dir}? [Y/n]: " choice
            if [[ ! "${choice,,}" =~ ^n ]]; then
                mkdir -p "$(dirname "${target_dir}")"
                [[ -d "${target_dir}" ]] && rm -rf "${target_dir}"
                cp -a "${sp}" "${target_dir}"
                ok "Copied to ${target_dir}"
                return 0
            else
                FREEFILESYNC_INSTALL_DIR="${sp}"
                return 0
            fi
        fi
    done

    # Ask the user
    echo ""
    warn "Could not locate FreeFileSync automatically."
    read -rp "Enter the path where you installed FreeFileSync (or 'skip'): " user_path

    if [[ "${user_path}" == "skip" || -z "${user_path}" ]]; then
        warn "FreeFileSync installation skipped."
        return 1
    fi

    if [[ -x "${user_path}/FreeFileSync" ]]; then
        if [[ "${user_path}" != "${target_dir}" ]]; then
            mkdir -p "$(dirname "${target_dir}")"
            [[ -d "${target_dir}" ]] && rm -rf "${target_dir}"
            cp -a "${user_path}" "${target_dir}"
            ok "Copied to ${target_dir}"
        fi
        return 0
    else
        err "FreeFileSync binary not found at ${user_path}/FreeFileSync"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# install_freefilesync — Download, extract, and install FreeFileSync
# ---------------------------------------------------------------------------

install_freefilesync() {
    local ffs_bin="${FREEFILESYNC_INSTALL_DIR}/FreeFileSync"

    if [[ -x "${ffs_bin}" ]]; then
        ok "FreeFileSync is already installed at ${FREEFILESYNC_INSTALL_DIR}"
        post_install_freefilesync "${FREEFILESYNC_INSTALL_DIR}"
        return 0
    fi

    local download_url="https://freefilesync.org/download/FreeFileSync_${FREEFILESYNC_VERSION}_Linux_x86_64.tar.gz"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local tar_file="${tmp_dir}/FreeFileSync_${FREEFILESYNC_VERSION}_Linux_x86_64.tar.gz"
    local download_ok=false

    info "Downloading FreeFileSync v${FREEFILESYNC_VERSION}..."

    # Try wget, then curl
    if command -v wget &>/dev/null; then
        if wget -q --user-agent="Mozilla/5.0" \
                -O "${tar_file}" "${download_url}" 2>/dev/null; then
            download_ok=true
        fi
    fi
    if [[ "${download_ok}" == false ]] && command -v curl &>/dev/null; then
        if curl -fSL -A "Mozilla/5.0" \
                -o "${tar_file}" "${download_url}" 2>/dev/null; then
            download_ok=true
        fi
    fi

    if [[ "${download_ok}" == false ]]; then
        rm -rf "${tmp_dir}"
        err "Automatic download failed."
        err "Please download FreeFileSync manually:"
        err "  URL:         https://freefilesync.org/"
        err "  Install to:  ${FREEFILESYNC_INSTALL_DIR}"
        return 1
    fi

    # Validate archive
    if ! file "${tar_file}" | grep -qi "gzip"; then
        rm -rf "${tmp_dir}"
        err "Downloaded file is not a valid gzip archive."
        err "Please download FreeFileSync manually from https://freefilesync.org/"
        return 1
    fi

    info "Extracting archive..."
    local extract_dir="${tmp_dir}/extracted"
    mkdir -p "${extract_dir}"
    tar -xzf "${tar_file}" -C "${extract_dir}"

    # Find .run installer inside the extracted archive
    local run_file
    run_file="$(find "${extract_dir}" -name "*.run" -type f | head -1)" || true

    if [[ -n "${run_file}" ]]; then
        info "Found installer: $(basename "${run_file}")"
        chmod +x "${run_file}"

        if ! run_interactive_install "${run_file}" "${FREEFILESYNC_INSTALL_DIR}"; then
            rm -rf "${tmp_dir}"
            err "FreeFileSync installation was not completed."
            err "You can install it manually later from https://freefilesync.org/"
            return 1
        fi
    else
        # Fallback: no .run file — look for binary directly (older versions)
        local found_bin
        found_bin="$(find "${extract_dir}" -name "FreeFileSync" -type f | head -1)" || true

        if [[ -z "${found_bin}" ]]; then
            rm -rf "${tmp_dir}"
            err "Could not find FreeFileSync binary or .run installer in the archive."
            err "Please install manually to: ${FREEFILESYNC_INSTALL_DIR}"
            return 1
        fi

        local source_dir
        source_dir="$(dirname "${found_bin}")"
        mkdir -p "$(dirname "${FREEFILESYNC_INSTALL_DIR}")"
        [[ -d "${FREEFILESYNC_INSTALL_DIR}" ]] && rm -rf "${FREEFILESYNC_INSTALL_DIR}"
        cp -a "${source_dir}" "${FREEFILESYNC_INSTALL_DIR}"
    fi

    # Ensure binaries are executable
    chmod +x "${FREEFILESYNC_INSTALL_DIR}/FreeFileSync"  2>/dev/null || true
    chmod +x "${FREEFILESYNC_INSTALL_DIR}/RealTimeSync"  2>/dev/null || true

    rm -rf "${tmp_dir}"

    if [[ -x "${FREEFILESYNC_INSTALL_DIR}/FreeFileSync" ]]; then
        ok "FreeFileSync v${FREEFILESYNC_VERSION} installed at ${FREEFILESYNC_INSTALL_DIR}"
        post_install_freefilesync "${FREEFILESYNC_INSTALL_DIR}"
    else
        warn "FreeFileSync extraction completed but the binary may not be executable."
        warn "Please check: ${FREEFILESYNC_INSTALL_DIR}"
    fi
}