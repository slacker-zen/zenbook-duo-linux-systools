#!/usr/bin/env bash
set -euo pipefail

# System-wide install, user-session runtime:
# files/config/sudoers are installed globally, while KDE/Wayland display
# behavior runs from the logged-in user's systemd manager.

INSTALL_LOCATION=/usr/bin/zenbook-duo-systools-fnkeys
CONFIG_LOCATION=/etc/zenbook-duo/fnkeys.conf
SUDOERS_LOCATION=/etc/sudoers.d/zenbook-duo-systools-fnkeys
SERVICE_LOCATION=/etc/systemd/user/zenbook-duo-systools-fnkeys.service
DEV_MODE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_INSTALL_LOCATION="${SCRIPT_DIR}/duo-fnkeys.sh"
PACKAGES=(
    bluez-utils
    glib2
    inotify-tools
    kscreen
    libinput
    libnotify
    networkmanager
    python-pyusb
    qt6-tools
    sudo
    usbutils
)

if [[ "${1:-}" == "--dev-mode" ]]; then
    DEV_MODE=true
    INSTALL_LOCATION="${DEV_INSTALL_LOCATION}"
fi

if [[ "${DEV_MODE}" == false ]]; then
    sudo pacman -Sy --needed --noconfirm "${PACKAGES[@]}"
    sudo install -Dm755 "${SCRIPT_DIR}/duo-fnkeys.sh" "${INSTALL_LOCATION}"
    sudo install -Dm644 "${SCRIPT_DIR}/fnkeys.conf" "${CONFIG_LOCATION}"
    sudo install -Dm755 "${SCRIPT_DIR}/backlight.py" /usr/lib/zenbook-duo-fnkeys/backlight.py
fi

if [[ "${DEV_MODE}" == false ]]; then
    sudo install -Dm440 "${SCRIPT_DIR}/sudoers-zenbook-duo-systools-fnkeys" "${SUDOERS_LOCATION}"
    sudo install -Dm644 "${SCRIPT_DIR}/zenbook-duo-systools-fnkeys.service" "${SERVICE_LOCATION}"

    echo "Installed ${INSTALL_LOCATION}."
    echo "Installed ${CONFIG_LOCATION}."
    if ! command -v kscreen-doctor >/dev/null 2>&1 && ! command -v gdctl >/dev/null 2>&1; then
        echo "Note: neither kscreen-doctor nor gdctl was found. Install one if you want fnkeys to switch display layouts."
    fi
    if ! command -v bluetoothctl >/dev/null 2>&1; then
        echo "Note: bluetoothctl was not found. Bluetooth keyboard detection will rely on libinput or USB only."
    fi
    if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
        echo "Note: current desktop is '${XDG_CURRENT_DESKTOP:-unknown}'. This setup is tuned for KDE Plasma Wayland, with gdctl fallback."
    fi
    echo "Enable the fnkey helper service with:"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable --now zenbook-duo-systools-fnkeys.service"
else
    echo "Dev mode selected. Run fnkeys directly from:"
    echo "  ${INSTALL_LOCATION}"
fi
