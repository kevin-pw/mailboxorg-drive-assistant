#!/usr/bin/env bash
#
# start-sync.sh — Manually start or restart mailbox.org Drive sync
#
# Usage: ./start-sync.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Output helpers
info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[ OK ]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()   { echo -e "\033[0;31m[ERR ]\033[0m  $*" >&2; }

# shellcheck source=drive.conf
source "${SCRIPT_DIR}/drive.conf"

version="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo 'unknown')"
info "mailbox.org Drive sync — version ${version}"

# ── Mount if needed ──────────────────────────────────────────────────

if ! mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
    info "Drive not mounted. Mounting ${MOUNT_POINT}..."
    if sg davfs2 -c "mount '${MOUNT_POINT}'" 2>/dev/null; then
        ok "Drive mounted"
    elif sudo mount "${MOUNT_POINT}" 2>/dev/null; then
        warn "Mounted with sudo — permissions may be restricted"
    else
        err "Could not mount drive at ${MOUNT_POINT}"
        err "Check your credentials and network connection."
        exit 1
    fi
else
    ok "Drive is already mounted at ${MOUNT_POINT}"
fi

# ── Stop existing RealTimeSync if running ────────────────────────────

if pgrep -f "RealTimeSync.*BatchRun" >/dev/null 2>&1; then
    info "Stopping existing RealTimeSync..."
    pkill -f "RealTimeSync.*BatchRun" 2>/dev/null || true
    sleep 1
    ok "Stopped"
fi

# ── Start RealTimeSync ───────────────────────────────────────────────

RTS_BIN="${FREEFILESYNC_INSTALL_DIR}/RealTimeSync"
REAL_FILE="${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_real"
BATCH_FILE="${FREEFILESYNC_INSTALL_DIR}/BatchRun.ffs_batch"

if [[ ! -x "${RTS_BIN}" ]]; then
    err "RealTimeSync not found at ${RTS_BIN}"
    exit 1
fi

if [[ ! -f "${REAL_FILE}" ]]; then
    err "RealTimeSync config not found: ${REAL_FILE}"
    exit 1
fi

if [[ ! -f "${BATCH_FILE}" ]]; then
    err "Batch config not found: ${BATCH_FILE}"
    exit 1
fi

info "Starting RealTimeSync..."
nohup "${RTS_BIN}" "${REAL_FILE}" >/dev/null 2>&1 &
disown

sleep 3

if pgrep -f "RealTimeSync" >/dev/null 2>&1; then
    ok "RealTimeSync is running"
    ok "Synchronisation is active"
    echo ""
    info "Two red arrows should appear in the taskbar."
    info "Your working directory is: ${LOCAL_DIR}"
else
    err "RealTimeSync did not start."
    err "Try running manually: ${RTS_BIN} ${REAL_FILE}"
    exit 1
fi