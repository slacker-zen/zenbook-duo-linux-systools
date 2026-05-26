#!/usr/bin/env bash
set -euo pipefail

# System-wide install:
# power/sleep behavior is system-level; KDE/Wayland display and keyboard
# events run through zenbook-duo-matrix.service.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_LOCATION=/usr/bin/zenbook-duo-systools
CONFIG_LOCATION=/etc/zenbook-duo/duo-sysstates.conf
SUDOERS_LOCATION=/etc/sudoers.d/zenbook-duo-systools
SYSTEM_SERVICE_LOCATION=/etc/systemd/system/zenbook-duo-systools.service
SLEEP_HOOK_LOCATION=/usr/lib/systemd/system-sleep/zenbook-duo-systools
DEV_MODE=false
PACKAGES=(
  bluez-utils
  kscreen
  power-profiles-daemon
  qt6-tools
  sudo
)

if [[ "${1:-}" == "--dev-mode" ]]; then
  DEV_MODE=true
  INSTALL_LOCATION="${SCRIPT_DIR}/duo-sysstates.sh"
fi

if [[ "${DEV_MODE}" == false ]]; then
  sudo pacman -Sy --needed --noconfirm "${PACKAGES[@]}"
  sudo install -Dm755 "${SCRIPT_DIR}/duo-sysstates.sh" "${INSTALL_LOCATION}"
  sudo install -Dm644 "${SCRIPT_DIR}/duo-sysstates.conf" "${CONFIG_LOCATION}"
  sudo install -Dm440 "${SCRIPT_DIR}/sudoers-zenbook-duo-systools" "${SUDOERS_LOCATION}"
  sudo install -Dm644 "${SCRIPT_DIR}/zenbook-duo-systools.service" "${SYSTEM_SERVICE_LOCATION}"
  sudo install -Dm755 "${SCRIPT_DIR}/zenbook-duo-systools.sleep" "${SLEEP_HOOK_LOCATION}"
  sudo systemctl daemon-reload

  echo "Installed ${INSTALL_LOCATION}."
  echo "Installed ${CONFIG_LOCATION}."
  if ! command -v kscreen-doctor >/dev/null 2>&1; then
    echo "Note: kscreen-doctor was not found. Display layout changes need KDE kscreen on this system."
  fi
  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    echo "Note: powerprofilesctl was not found. Power profile changes will be skipped."
  fi
  if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
    echo "Note: current desktop is '${XDG_CURRENT_DESKTOP:-unknown}'. This setup is tuned for KDE Plasma Wayland."
  fi
  echo "Enable the system power/lid policy service with:"
  echo "  sudo systemctl enable --now zenbook-duo-systools.service"
  echo "User-session display events are handled by zenbook-duo-matrix.service."
else
  echo "Dev mode selected. Run sysstates directly from:"
  echo "  ${INSTALL_LOCATION}"
fi
