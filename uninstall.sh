#!/usr/bin/env bash
#
# uninstall.sh — Remove the mailbox.org Drive setup
#
# Reverses everything performed by setup.sh.  Destructive actions
# require explicit confirmation.
#
# Usage: ./uninstall.sh
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
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

if [[ "$EUID" -eq 0 ]]; then
    err "Do not run as root. Run as your normal user."
    exit 1
fi

# shellcheck source=setup.conf
source "${SCRIPT_DIR}/setup.conf"
CURRENT_USER="$(whoami)"

echo ""
echo "================================================"
echo "   mailbox.org Drive — Uninstall"
echo "================================================"
echo ""
warn "This will remove the mailbox.org Drive configuration from your system."
echo ""

# Allow overriding defaults
read -rp "Mount point [${MOUNT_POINT}]: " input
MOUNT_POINT="${input:-${MOUNT_POINT}}"

read -rp "Local sync directory [${LOCAL_DIR}]: " input
LOCAL_DIR="${input:-${LOCAL_DIR}}"

read -rp "FreeFileSync install directory [${FREEFILESYNC_INSTALL_DIR}]: " input
FREEFILESYNC_INSTALL_DIR="${input:-${FREEFILESYNC_INSTALL_DIR}}"

echo ""
read -rp "Proceed with uninstall? [y/N]: " confirm
if [[ ! "${confirm,,}" =~ ^y ]]; then
    info "Uninstall cancelled."
    exit 0
fi

# ---------------------------------------------------------------------------
# Sudo keepalive
# ---------------------------------------------------------------------------

info "Requesting sudo access..."
sudo -v
while true; do
    sudo -n true 2>/dev/null
    sleep 55
    kill -0 "$$" 2>/dev/null || exit
done &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
      wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT

echo ""

# ---------------------------------------------------------------------------
# Stop running processes
# ---------------------------------------------------------------------------

info "Stopping RealTimeSync if running..."
if pkill -f "RealTimeSync" 2>/dev/null; then
    ok "RealTimeSync stopped"
else
    info "RealTimeSync was not running"
fi

# ---------------------------------------------------------------------------
# Stop and remove periodic sync timer
# ---------------------------------------------------------------------------

info "Removing periodic sync timer..."
if systemctl --user is-active mailbox-drive-sync.timer &>/dev/null; then
    systemctl --user stop mailbox-drive-sync.timer 2>/dev/null || true
    ok "Timer stopped"
fi
if systemctl --user is-enabled mailbox-drive-sync.timer &>/dev/null; then
    systemctl --user disable mailbox-drive-sync.timer 2>/dev/null || true
    ok "Timer disabled"
fi
for f in mailbox-drive-sync.service mailbox-drive-sync.timer; do
    if [[ -f "${HOME}/.config/systemd/user/${f}" ]]; then
        rm -f "${HOME}/.config/systemd/user/${f}"
        ok "Removed ${f}"
    fi
done
systemctl --user daemon-reload 2>/dev/null || true

# ---------------------------------------------------------------------------
# Unmount drive
# ---------------------------------------------------------------------------

info "Unmounting drive..."
if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
    if sudo umount "${MOUNT_POINT}" 2>/dev/null; then
        ok "Drive unmounted"
    else
        warn "Could not unmount ${MOUNT_POINT} — it may be in use"
    fi
else
    info "Drive is not currently mounted"
fi

# ---------------------------------------------------------------------------
# Remove autostart entries
# ---------------------------------------------------------------------------

info "Removing autostart entries..."
for f in mount-mailbox-drive.desktop realtimesync-mailbox.desktop; do
    if [[ -f "${HOME}/.config/autostart/${f}" ]]; then
        rm -f "${HOME}/.config/autostart/${f}"
        ok "Removed ${f}"
    fi
done

# ---------------------------------------------------------------------------
# Remove helper scripts
# ---------------------------------------------------------------------------

info "Removing helper scripts..."
for f in mount-mailbox-drive start-realtimesync-mailbox; do
    if [[ -f "${HOME}/.local/bin/${f}" ]]; then
        rm -f "${HOME}/.local/bin/${f}"
        ok "Removed ${f}"
    fi
done

# ---------------------------------------------------------------------------
# Remove fstab entry
# ---------------------------------------------------------------------------

info "Checking /etc/fstab..."
if grep -q "${MOUNT_POINT}.*davfs" /etc/fstab 2>/dev/null; then
    sudo cp /etc/fstab /etc/fstab.bak
    sudo sed -i "\|${MOUNT_POINT}.*davfs|d" /etc/fstab
    ok "fstab entry removed (backup at /etc/fstab.bak)"
else
    info "No fstab entry found for ${MOUNT_POINT}"
fi

# ---------------------------------------------------------------------------
# Remove credentials from secrets file
# ---------------------------------------------------------------------------

info "Removing credentials from davfs2 secrets..."
if sudo grep -q "^${MOUNT_POINT} " /etc/davfs2/secrets 2>/dev/null; then
    sudo sed -i "\|^${MOUNT_POINT} |d" /etc/davfs2/secrets
    ok "Credentials removed"
else
    info "No credentials found for ${MOUNT_POINT}"
fi

# ---------------------------------------------------------------------------
# Restore davfs2.conf
# ---------------------------------------------------------------------------

if [[ -f /etc/davfs2/davfs2.conf.orig ]]; then
    echo ""
    read -rp "Restore original davfs2.conf? [y/N]: " choice
    if [[ "${choice,,}" =~ ^y ]]; then
        sudo mv /etc/davfs2/davfs2.conf.orig /etc/davfs2/davfs2.conf
        ok "Original davfs2.conf restored"
    fi
fi

# ---------------------------------------------------------------------------
# Remove user from davfs2 group
# ---------------------------------------------------------------------------

if id -nG "${CURRENT_USER}" 2>/dev/null | grep -qw "davfs2"; then
    echo ""
    read -rp "Remove user '${CURRENT_USER}' from davfs2 group? [y/N]: " choice
    if [[ "${choice,,}" =~ ^y ]]; then
        sudo gpasswd -d "${CURRENT_USER}" davfs2
        ok "User removed from davfs2 group"
    fi
fi

# ---------------------------------------------------------------------------
# Remove mount point
# ---------------------------------------------------------------------------

if [[ -d "${MOUNT_POINT}" ]]; then
    echo ""
    read -rp "Remove mount point directory ${MOUNT_POINT}? [y/N]: " choice
    if [[ "${choice,,}" =~ ^y ]]; then
        sudo rm -rf "${MOUNT_POINT}"
        ok "Mount point removed"
    fi
fi

# ---------------------------------------------------------------------------
# Remove local directory  *** DESTRUCTIVE ***
# ---------------------------------------------------------------------------

if [[ -d "${LOCAL_DIR}" ]]; then
    echo ""
    warn "Your local sync directory may contain important files:"
    warn "  ${LOCAL_DIR}"
    read -rp "Remove local directory and ALL its contents? [y/N]: " choice
    if [[ "${choice,,}" =~ ^y ]]; then
        rm -rf "${LOCAL_DIR}"
        ok "Local directory removed"
    else
        info "Local directory preserved at ${LOCAL_DIR}"
    fi
fi

# ---------------------------------------------------------------------------
# Remove FreeFileSync
# ---------------------------------------------------------------------------

if [[ -d "${FREEFILESYNC_INSTALL_DIR}" ]]; then
    echo ""
    read -rp "Remove FreeFileSync installation? [y/N]: " choice
    if [[ "${choice,,}" =~ ^y ]]; then

        if [[ -x "${FREEFILESYNC_INSTALL_DIR}/uninstall.sh" ]]; then
            info "Running FreeFileSync's built-in uninstaller..."
            bash "${FREEFILESYNC_INSTALL_DIR}/uninstall.sh" 2>/dev/null || true
            ok "FreeFileSync uninstaller completed"
        else
            info "No built-in uninstaller found; removing manually..."
        fi

        # Clean up anything the uninstaller may have left behind
        if [[ -d "${FREEFILESYNC_INSTALL_DIR}" ]]; then
            rm -rf "${FREEFILESYNC_INSTALL_DIR}"
            info "Removed ${FREEFILESYNC_INSTALL_DIR}"
        fi

        # Remove symlinks
        for link in "${HOME}/.local/bin/FreeFileSync" \
                     "${HOME}/.local/bin/freefilesync"; do
            if [[ -L "${link}" || -e "${link}" ]]; then
                rm -f "${link}"
                info "Removed symlink: ${link}"
            fi
        done

        # Remove .desktop entries
        for f in FreeFileSync.desktop RealTimeSync.desktop; do
            if [[ -f "${HOME}/.local/share/applications/${f}" ]]; then
                rm -f "${HOME}/.local/share/applications/${f}"
                info "Removed application entry: ${f}"
            fi
        done

        if command -v update-desktop-database &>/dev/null; then
            update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
        fi

        ok "FreeFileSync removed"
    fi
fi

# ---------------------------------------------------------------------------
# Optionally uninstall davfs2 system package
# ---------------------------------------------------------------------------

echo ""
read -rp "Uninstall davfs2 system package? [y/N]: " choice
if [[ "${choice,,}" =~ ^y ]]; then
    sudo apt-get remove -y davfs2
    ok "davfs2 package removed"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo "================================================"
echo "   Uninstall Complete"
echo "================================================"
echo ""
ok "mailbox.org Drive setup has been removed."
if id -nG "${CURRENT_USER}" 2>/dev/null | grep -qw "davfs2"; then
    warn "Group changes require logout or reboot to take full effect."
fi
echo ""