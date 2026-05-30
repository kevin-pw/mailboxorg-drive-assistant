#!/usr/bin/env bash
#
# setup.sh — Automated setup for mailbox.org Drive on Ubuntu
#
# Usage: ./setup.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()    { echo -e "${RED}[ERR ]${NC}  $*" >&2; }
header() { echo -e "\n${BOLD}=== $* ===${NC}"; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

if [[ "$EUID" -eq 0 ]]; then
    err "Do not run this script as root."
    err "Run as your normal user; sudo will be requested when needed."
    exit 1
fi

for f in VERSION \
         drive.conf \
         templates/BatchRun.ffs_batch \
         templates/BatchRun.ffs_real \
         scripts/install-deps.sh \
         scripts/configure-davfs.sh \
         scripts/configure-mount.sh \
         scripts/configure-sync.sh \
         scripts/configure-autostart.sh; do
    if [[ ! -f "${SCRIPT_DIR}/${f}" ]]; then
        err "Missing required file: ${f}"
        err "Please run this script from the repository root directory."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Load defaults and helper functions
# ---------------------------------------------------------------------------

# shellcheck source=drive.conf
source "${SCRIPT_DIR}/drive.conf"

# shellcheck source=scripts/install-deps.sh
source "${SCRIPT_DIR}/scripts/install-deps.sh"
# shellcheck source=scripts/configure-davfs.sh
source "${SCRIPT_DIR}/scripts/configure-davfs.sh"
# shellcheck source=scripts/configure-mount.sh
source "${SCRIPT_DIR}/scripts/configure-mount.sh"
# shellcheck source=scripts/configure-sync.sh
source "${SCRIPT_DIR}/scripts/configure-sync.sh"
# shellcheck source=scripts/configure-autostart.sh
source "${SCRIPT_DIR}/scripts/configure-autostart.sh"

# ---------------------------------------------------------------------------
# Phase 1 — Interactive configuration
# ---------------------------------------------------------------------------

phase_configure() {
    local version
    version="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo 'unknown')"
    
    echo ""
    echo "================================================"
    echo "   mailbox.org Drive — Setup for Ubuntu"
    echo "   Version: ${version}"
    echo "================================================"
    echo ""
    info "This script will:"
    info "  • Install and configure davfs2 for WebDAV access"
    info "  • Mount your mailbox.org Drive at a local path"
    info "  • Install FreeFileSync for offline synchronisation"
    info "  • Configure autostart entries for mount and sync"
    echo ""

    read -rp "WebDAV URL [${WEBDAV_URL}]: " input
    WEBDAV_URL="${input:-${WEBDAV_URL}}"

    read -rp "Mount point for online drive [${MOUNT_POINT}]: " input
    MOUNT_POINT="${input:-${MOUNT_POINT}}"

    read -rp "Local sync directory [${LOCAL_DIR}]: " input
    LOCAL_DIR="${input:-${LOCAL_DIR}}"

    read -rp "FreeFileSync version [${FREEFILESYNC_VERSION}]: " input
    FREEFILESYNC_VERSION="${input:-${FREEFILESYNC_VERSION}}"

    read -rp "FreeFileSync install directory [${FREEFILESYNC_INSTALL_DIR}]: " input
    FREEFILESYNC_INSTALL_DIR="${input:-${FREEFILESYNC_INSTALL_DIR}}"

    read -rp "RealTimeSync delay in seconds [${FREEFILESYNC_DELAY_SECONDS}]: " input
    FREEFILESYNC_DELAY_SECONDS="${input:-${FREEFILESYNC_DELAY_SECONDS}}"

    echo ""
    read -rp "mailbox.org email address: " MAILBOX_EMAIL
    if [[ -z "${MAILBOX_EMAIL}" ]]; then
        err "Email address is required."
        exit 1
    fi

    echo ""
    info "Enter your mailbox.org app password."
    info "Use a dedicated app password — not your main login password."
    info "(See README.md for instructions on creating one.)"
    read -rsp "App password (input is hidden): " MAILBOX_PASSWORD
    echo ""
    if [[ -z "${MAILBOX_PASSWORD}" ]]; then
        err "Password is required."
        exit 1
    fi

    CURRENT_USER="$(whoami)"
    CURRENT_GROUP="$(id -gn)"

    # Display name will be auto-detected after test mount in Phase 4
    MAILBOX_DISPLAY_NAME=""
    MAILBOX_DISPLAY_NAME_CANDIDATES=()

    echo ""
    echo "================================================"
    echo "   Configuration Summary"
    echo "================================================"
    echo "  WebDAV URL:          ${WEBDAV_URL}"
    echo "  Mount point:         ${MOUNT_POINT}"
    echo "  Local directory:     ${LOCAL_DIR}"
    echo "  Email:               ${MAILBOX_EMAIL}"
    echo "  Password:            ********"
    echo "  FreeFileSync:        v${FREEFILESYNC_VERSION}"
    echo "  Install directory:   ${FREEFILESYNC_INSTALL_DIR}"
    echo "  Sync delay:          ${FREEFILESYNC_DELAY_SECONDS}s"
    echo "  System user:         ${CURRENT_USER}"
    echo "  Display name:        (will be auto-detected)"
    echo "================================================"
    echo ""

    read -rp "Proceed with setup? [Y/n]: " confirm
    if [[ "${confirm,,}" =~ ^n ]]; then
        info "Setup cancelled."
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# Resolve display name — auto-detected in Phase 4 or prompted here
# ---------------------------------------------------------------------------

resolve_display_name() {
    # Case 1: Successfully auto-detected (single directory)
    if [[ -n "${MAILBOX_DISPLAY_NAME}" ]]; then
        echo ""
        info "Auto-detected mailbox display name: ${MAILBOX_DISPLAY_NAME}"
        read -rp "Use this name? [Y/n]: " confirm
        if [[ "${confirm,,}" =~ ^n ]]; then
            read -rp "Enter correct display name: " MAILBOX_DISPLAY_NAME
        fi
    # Case 2: Multiple candidates found
    elif [[ ${#MAILBOX_DISPLAY_NAME_CANDIDATES[@]} -gt 0 ]]; then
        echo ""
        info "Multiple directories found in your drive."
        info "Select the one that contains your files:"
        echo ""
        for i in "${!MAILBOX_DISPLAY_NAME_CANDIDATES[@]}"; do
            echo "  $((i+1)). ${MAILBOX_DISPLAY_NAME_CANDIDATES[$i]}"
        done
        echo ""
        while true; do
            read -rp "Enter number [1-${#MAILBOX_DISPLAY_NAME_CANDIDATES[@]}]: " choice
            if [[ "${choice}" =~ ^[0-9]+$ ]] \
               && [[ "${choice}" -ge 1 ]] \
               && [[ "${choice}" -le ${#MAILBOX_DISPLAY_NAME_CANDIDATES[@]} ]]; then
                MAILBOX_DISPLAY_NAME="${MAILBOX_DISPLAY_NAME_CANDIDATES[$((choice-1))]}"
                break
            fi
            warn "Invalid selection. Please try again."
        done
    # Case 3: Nothing detected — manual entry
    else
        echo ""
        warn "Could not auto-detect your mailbox display name."
        info "This is the folder inside your mounted drive that contains your files."
        info "It is typically your full name (e.g. 'Max Mustermann')."
        info "You can find it in your mailbox.org account settings."
        echo ""
        read -rp "Mailbox display name: " MAILBOX_DISPLAY_NAME
    fi

    if [[ -z "${MAILBOX_DISPLAY_NAME}" ]]; then
        err "Display name is required for sync configuration."
        exit 1
    fi

    ok "Using display name: ${MAILBOX_DISPLAY_NAME}"
}

# ---------------------------------------------------------------------------
# Phase 7 — Activate mount and sync immediately
# ---------------------------------------------------------------------------

activate_now() {
    # ── Mount the drive ──────────────────────────────────────────────
    # Use sg to activate the davfs2 group membership that was added via
    # usermod in Phase 3.  This avoids sudo mount, which would make the
    # mount root-owned and cause permission errors for the regular user.
    info "Mounting drive at ${MOUNT_POINT}..."

    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        ok "Drive is already mounted"
    elif mount_as_user; then
        ok "Drive mounted at ${MOUNT_POINT}"
    else
        warn "Could not mount drive."
        warn "Try manually:  sg davfs2 -c \"mount '${MOUNT_POINT}'\""
        return 0
    fi

    # ── Verify drive contents ────────────────────────────────────────
    if [[ -d "${MOUNT_POINT}/${MAILBOX_DISPLAY_NAME}" ]]; then
        ok "Drive folder accessible: ${MOUNT_POINT}/${MAILBOX_DISPLAY_NAME}"
    else
        warn "Expected folder not found: ${MOUNT_POINT}/${MAILBOX_DISPLAY_NAME}"
        warn "Sync may not work correctly until this folder exists."
    fi

    # ── Verify write access ──────────────────────────────────────────
    local test_file="${MOUNT_POINT}/${MAILBOX_DISPLAY_NAME}/.write_test_$$"
    if touch "${test_file}" 2>/dev/null; then
        rm -f "${test_file}" 2>/dev/null || true
        ok "Write access verified"
    else
        warn "Cannot write to ${MOUNT_POINT}/${MAILBOX_DISPLAY_NAME}"
        warn "FreeFileSync may show lock file warnings."
        warn "Try remounting: umount '${MOUNT_POINT}' && sg davfs2 -c \"mount '${MOUNT_POINT}'\""
    fi

    # ── Start RealTimeSync ───────────────────────────────────────────
    local rts_bin="${FREEFILESYNC_INSTALL_DIR}/RealTimeSync"
    local real_file="${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_real"
    local batch_file="${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_batch"

    if [[ ! -x "${rts_bin}" ]]; then
        warn "RealTimeSync binary not found at ${rts_bin}"
        warn "Start it manually after installation."
        return 0
    fi

    if [[ ! -f "${real_file}" ]]; then
        warn "RealTimeSync config not found: ${real_file}"
        return 0
    fi

    if [[ ! -f "${batch_file}" ]]; then
        warn "Batch config not found: ${batch_file}"
        return 0
    fi

    if pgrep -f "RealTimeSync.*BatchRun" >/dev/null 2>&1; then
        ok "RealTimeSync is already running"
        return 0
    fi

    info "Starting RealTimeSync..."
    nohup "${rts_bin}" "${real_file}" >/dev/null 2>&1 &
    disown

    # Give it a moment to start
    sleep 3

    if pgrep -f "RealTimeSync" >/dev/null 2>&1; then
        ok "RealTimeSync is running"
        ok "Synchronisation is active"
    else
        warn "RealTimeSync may not have started correctly."
        warn "You can start it manually:"
        warn "  ${rts_bin} ${real_file}"
    fi
}

# ---------------------------------------------------------------------------
# Sudo keepalive — authenticate once, refresh in background
# ---------------------------------------------------------------------------

start_sudo_keepalive() {
    info "Requesting sudo access (you will be prompted once)..."
    sudo -v
    while true; do
        sudo -n true 2>/dev/null
        sleep 55
        kill -0 "$$" 2>/dev/null || exit
    done &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
        wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    phase_configure

    start_sudo_keepalive
    trap stop_sudo_keepalive EXIT
    trap 'err "Setup failed at line ${LINENO}. Check the output above."' ERR

    header "Phase 2: Installing dependencies"
    install_dependencies

    header "Phase 3: Configuring davfs2"
    configure_davfs

    header "Phase 4: Setting up directories and testing mount"
    configure_mount

    # Display name is auto-detected during Phase 4 test mount.
    # Confirm or prompt before proceeding.
    header "Phase 4b: Confirming mailbox display name"
    resolve_display_name

    header "Phase 5: Configuring synchronisation"
    configure_sync

    header "Phase 6: Configuring autostart"
    configure_autostart

    # Clear password from memory
    unset MAILBOX_PASSWORD

    header "Phase 7: Activating drive and sync"
    activate_now

    stop_sudo_keepalive
    trap - EXIT ERR

    echo ""
    echo "================================================"
    echo "   Setup Complete — Drive is Active"
    echo "================================================"
    echo ""
    ok "davfs2 installed and configured"
    ok "WebDAV drive mounted at ${MOUNT_POINT}"
    ok "Local sync directory ready at ${LOCAL_DIR}"
    ok "FreeFileSync installed at ${FREEFILESYNC_INSTALL_DIR}"
    ok "Sync active: ${MOUNT_POINT}/${MAILBOX_DISPLAY_NAME} ↔ ${LOCAL_DIR}"
    ok "RealTimeSync running — two red arrows should appear in the taskbar"
    ok "Autostart entries created for next login"
    echo ""
    info "Files created:"
    info "  Batch config:     ${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_batch"
    info "  RealTimeSync:     ${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_real"
    info "  Mount helper:     ${HOME}/.local/bin/mount-mailbox-drive"
    info "  Sync helper:      ${HOME}/.local/bin/start-realtimesync-mailbox"
    info "  Mount autostart:  ${HOME}/.config/autostart/mount-mailbox-drive.desktop"
    info "  Sync autostart:   ${HOME}/.config/autostart/realtimesync-mailbox.desktop"
    echo ""
    info "Your working directory is: ${LOCAL_DIR}"
    info "Save files there and they will sync to your mailbox.org Drive automatically."
    echo ""
}

main "$@"