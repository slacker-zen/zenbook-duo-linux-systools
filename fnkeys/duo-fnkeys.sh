#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/zenbook-duo/fnkeys.conf"
HELPER_VERSION="1.0"
TMP_DIR="/tmp/duo"
BACKLIGHT_PY_SYSTEM="/usr/lib/zenbook-duo-fnkeys/backlight.py"
DEFAULT_BACKLIGHT=1
DEFAULT_SCALE=1
DEFAULT_MAIN_SCREEN="eDP-1"
DEFAULT_LOWER_SCREEN="eDP-2"
DEFAULT_MAIN_BACKLIGHT="/sys/class/backlight/intel_backlight/brightness"
DEFAULT_LOWER_BACKLIGHT="/sys/class/backlight/card1-eDP-2-backlight/brightness"
DEFAULT_KEYBOARD_USB_MATCH="Primax|ASUS.*Keyboard|ASUSTeK.*Keyboard|Zenbook Duo.*Keyboard|0b05:1b2[cd]"
DEFAULT_KEYBOARD_DOCK_USB_PATH="3-6"
DEFAULT_KEYBOARD_BT_MAC="E9:C7:F1:96:05:3C"
DEFAULT_KEYBOARD_BT_NAME="ASUS Zenbook Duo Keyboard"
DEFAULT_LOWER_POSITION="0,1200"

mkdir -p "${TMP_DIR}"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
fi

BACKLIGHT_LEVEL="${FNKEYS_BACKLIGHT_LEVEL:-$DEFAULT_BACKLIGHT}"
SCALE="${DUO_MONITOR_SCALE:-$DEFAULT_SCALE}"
MAIN_SCREEN="${DUO_MAIN_SCREEN:-$DEFAULT_MAIN_SCREEN}"
LOWER_SCREEN="${DUO_LOWER_SCREEN:-$DEFAULT_LOWER_SCREEN}"
MAIN_BACKLIGHT_PATH="${FNKEYS_MAIN_BACKLIGHT_PATH:-$DEFAULT_MAIN_BACKLIGHT}"
LOWER_BACKLIGHT_PATH="${FNKEYS_LOWER_BACKLIGHT_PATH:-$DEFAULT_LOWER_BACKLIGHT}"
KEYBOARD_MATCH="${KEYBOARD_MATCH:-Primax|ASUS.*Zenbook Duo.*Keyboard|Zenbook Duo.*Keyboard}"
KEYBOARD_USB_MATCH="${FNKEYS_KEYBOARD_USB_MATCH:-$DEFAULT_KEYBOARD_USB_MATCH}"
KEYBOARD_DOCK_USB_PATH="${FNKEYS_KEYBOARD_DOCK_USB_PATH:-$DEFAULT_KEYBOARD_DOCK_USB_PATH}"
KEYBOARD_BT_MAC="${FNKEYS_KEYBOARD_BT_MAC:-$DEFAULT_KEYBOARD_BT_MAC}"
KEYBOARD_BT_NAME="${FNKEYS_KEYBOARD_BT_NAME:-$DEFAULT_KEYBOARD_BT_NAME}"
LOWER_POSITION="${FNKEYS_LOWER_POSITION:-$DEFAULT_LOWER_POSITION}"
MANAGE_DISPLAY="${FNKEYS_MANAGE_DISPLAY:-true}"
MANAGE_WIFI="${FNKEYS_MANAGE_WIFI:-false}"
MANAGE_BLUETOOTH="${FNKEYS_MANAGE_BLUETOOTH:-false}"
SYNC_DISPLAY_BACKLIGHT="${FNKEYS_SYNC_DISPLAY_BACKLIGHT:-false}"
REFRESH_PLASMA_ON_LAYOUT="${FNKEYS_REFRESH_PLASMA_ON_LAYOUT:-false}"
RESTART_PLASMA_ON_ATTACH="${FNKEYS_RESTART_PLASMA_ON_ATTACH:-false}"
MOVE_PLASMA_PANELS="${FNKEYS_MOVE_PLASMA_PANELS:-true}"
PLASMA_PANEL_SCREEN_ATTACHED="${FNKEYS_PLASMA_PANEL_SCREEN_ATTACHED:-0}"
PLASMA_PANEL_SCREEN_DETACHED="${FNKEYS_PLASMA_PANEL_SCREEN_DETACHED:-1}"
PYTHON3="$(command -v python3 || true)"
GDCTL="$(command -v gdctl || true)"
KSCREEN="$(command -v kscreen-doctor || true)"
BLUETOOTHCTL="$(command -v bluetoothctl || true)"
TEE="$(command -v tee || true)"
NOTIFY_SEND="$(command -v notify-send || true)"

trap 'echo "Ctrl+C captured. Exiting..."; pkill -P $$; exit 1' INT

function duo-write-backlight-script() {
  local dest="${1}"
  mkdir -p "$(dirname "${dest}")"
  cat > "${dest}" <<'PY'
#!/usr/bin/env python3
import os
import sys
import usb.core
import usb.util

VENDOR_ID = int(os.environ.get('DUO_VENDOR_ID', '0'), 16)
PRODUCT_ID = int(os.environ.get('DUO_PRODUCT_ID', '0'), 16)
REPORT_ID = 0x5A
WVALUE = 0x035A
WINDEX = 4
WLENGTH = 16

if VENDOR_ID == 0 or PRODUCT_ID == 0:
    print('Missing DUO_VENDOR_ID or DUO_PRODUCT_ID environment variables.')
    sys.exit(1)

if len(sys.argv) != 2:
    print(f'Usage: {sys.argv[0]} <level>')
    sys.exit(1)

try:
    level = int(sys.argv[1])
    if level < 0 or level > 3:
        raise ValueError
except ValueError:
    print('Invalid level. Must be an integer between 0 and 3.')
    sys.exit(1)

packet = [0] * WLENGTH
packet[0] = REPORT_ID
packet[1] = 0xBA
packet[2] = 0xC5
packet[3] = 0xC4
packet[4] = level

def find_device():
    return usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID)

def attach_kernel_driver(device):
    try:
        if device.is_kernel_driver_active(WINDEX):
            device.detach_kernel_driver(WINDEX)
            return True
    except Exception:
        pass
    return False


def main():
    dev = find_device()
    if dev is None:
        print(f'Device not found (Vendor ID: 0x{VENDOR_ID:04X}, Product ID: 0x{PRODUCT_ID:04X})')
        sys.exit(1)

    reattached = attach_kernel_driver(dev)
    try:
        ret = dev.ctrl_transfer(0x21, 0x09, WVALUE, WINDEX, packet, timeout=1000)
        if ret != WLENGTH:
            print(f'Warning: Only {ret} bytes sent out of {WLENGTH}.')
            sys.exit(1)
        print('Data packet sent successfully.')
    except usb.core.USBError as e:
        print(f'Control transfer failed: {e}')
        sys.exit(1)
    finally:
        try:
            usb.util.release_interface(dev, WINDEX)
        except Exception:
            pass
        if reattached:
            try:
                dev.attach_kernel_driver(WINDEX)
            except Exception:
                pass

if __name__ == '__main__':
    main()
PY
  chmod a+x "${dest}"
}

function duo-find-keyboard-usb() {
  lsusb | grep -F 'Zenbook Duo Keyboard' | awk '{print $6}' | head -n1 || true
}

function duo-has-keyboard-bluetooth() {
  [[ -n "${BLUETOOTHCTL}" ]] || return 1

  if [[ -n "${KEYBOARD_BT_MAC}" ]] && "${BLUETOOTHCTL}" info "${KEYBOARD_BT_MAC}" 2>/dev/null | grep -q "Connected: yes"; then
    return 0
  fi

  [[ -n "${KEYBOARD_BT_NAME}" ]] || return 1
  local mac
  mac=$("${BLUETOOTHCTL}" devices 2>/dev/null | awk -v name="${KEYBOARD_BT_NAME}" '
    BEGIN { IGNORECASE=1 }
    index($0, name) { print $2; exit }
  ' || true)
  [[ -n "${mac}" ]] || return 1
  "${BLUETOOTHCTL}" info "${mac}" 2>/dev/null | grep -q "Connected: yes"
}

function duo-usb-device-matches-dock-path() {
  local device="$1"
  local product="" manufacturer="" vendor="" product_id="" devpath="" haystack=""

  [[ -n "${KEYBOARD_DOCK_USB_PATH}" ]] || return 1

  [[ -r "${device}/product" ]] && product="$(<"${device}/product")"
  [[ -r "${device}/manufacturer" ]] && manufacturer="$(<"${device}/manufacturer")"
  [[ -r "${device}/idVendor" ]] && vendor="$(<"${device}/idVendor")"
  [[ -r "${device}/idProduct" ]] && product_id="$(<"${device}/idProduct")"
  [[ -r "${device}/devpath" ]] && devpath="$(<"${device}/devpath")"

  haystack="${device##*/} ${devpath} ${manufacturer} ${product} ${vendor}:${product_id}"
  [[ "${haystack}" =~ ${KEYBOARD_USB_MATCH} || "${haystack}" =~ ${KEYBOARD_MATCH} ]] || return 1
  [[ "${haystack}" =~ ${KEYBOARD_DOCK_USB_PATH} ]]
}

function duo-has-keyboard-attached() {
  # Attached means docked through the built-in keyboard connector. Bluetooth
  # and ordinary wired USB both leave the lower screen physically uncovered.
  local usb_device

  for usb_device in /sys/bus/usb/devices/*; do
    [[ -d "${usb_device}" ]] || continue
    if duo-usb-device-matches-dock-path "${usb_device}"; then
      return 0
    fi
  done

  return 1
}

function duo-set-status() {
  cat > "${TMP_DIR}/status" <<EOF
BLUETOOTH_BEFORE=${BLUETOOTH_BEFORE:-unblocked}
WIFI_BEFORE=${WIFI_BEFORE:-enabled}
KEYBOARD_ATTACHED=${KEYBOARD_ATTACHED:-false}
MONITOR_COUNT=${MONITOR_COUNT:-0}
EOF
}

function duo-ensure-backlight-script() {
  local path="${BACKLIGHT_PY_SYSTEM}"
  if [[ ! -x "${path}" ]]; then
    path="${TMP_DIR}/backlight.py"
    if [[ ! -f "${path}" ]]; then
      duo-write-backlight-script "${path}"
    fi
  fi
  printf '%s' "${path}"
}

function duo-normalize-backlight-level() {
  local value="${1}"
  if [[ ! "${value}" =~ ^[0-3]$ ]]; then
    echo "Invalid keyboard backlight level: ${value}. Expected 0, 1, 2, or 3." >&2
    return 1
  fi
  printf '%s' "${value}"
}

function duo-set-kb-backlight() {
  local target
  local led_path max brightness

  target="$(duo-normalize-backlight-level "${1}")"

  led_path=$(find /sys/class/leds -maxdepth 2 -type f \( -iname '*kbd*' -o -iname '*keyboard*' -o -iname '*asus*' \) -name brightness | head -n1 || true)
  if [[ -n "${led_path}" ]]; then
    max=$(<"${led_path%/*}/max_brightness" 2>/dev/null || echo 0)
    if [[ -z "${max}" || "${max}" -le 0 ]]; then
      max=3
    fi
    brightness=$(( max * target / 3 ))
    if (( target > 0 && brightness < 1 && max > 0 )); then
      brightness=1
    fi
    if (( brightness > max )); then
      brightness=${max}
    fi
    if [[ -w "${led_path}" ]]; then
      printf '%s' "${brightness}" >"${led_path}"
    else
      printf '%s' "${brightness}" | sudo ${TEE} "${led_path}" >/dev/null
    fi
    return
  fi

  if [[ -z "${PYTHON3}" ]]; then
    echo "Warning: python3 is not available for USB backlight control."
    return 1
  fi

  local keyboard_id vendor product backlight_script
  keyboard_id=$(duo-find-keyboard-usb)
  if [[ -z "${keyboard_id}" ]]; then
    echo "No Zenbook Duo keyboard device found for USB backlight control."
    return 0
  fi
  vendor=${keyboard_id%:*}
  product=${keyboard_id#*:}

  backlight_script=$(duo-ensure-backlight-script)
  DUO_VENDOR_ID="0x${vendor}" DUO_PRODUCT_ID="0x${product}" sudo "${PYTHON3}" "${backlight_script}" "${target}" >/dev/null 2>&1
}

function duo-sync-display-backlight() {
  [[ "${SYNC_DISPLAY_BACKLIGHT}" == true ]] || return 0
  if ! duo-has-keyboard-attached; then
    local cur_brightness
    cur_brightness=$(cat "${MAIN_BACKLIGHT_PATH}" 2>/dev/null || true)
    if [[ -n "${cur_brightness}" && "${cur_brightness}" != "${BRIGHTNESS:-}" ]]; then
      BRIGHTNESS="${cur_brightness}"
      echo "$(date) - DISPLAY - Setting brightness to $(printf '%s' "${BRIGHTNESS}" | sudo ${TEE} "${LOWER_BACKLIGHT_PATH}")"
    fi
  fi
}

function duo-refresh-plasma-shell() {
  [[ "${REFRESH_PLASMA_ON_LAYOUT}" == true ]] || return 0

  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell >/dev/null 2>&1 || true
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
  fi
}

function duo-restart-plasma-shell() {
  [[ "${RESTART_PLASMA_ON_ATTACH}" == true ]] || return 0

  if ! command -v plasmashell >/dev/null 2>&1; then
    return 0
  fi

  if command -v kquitapp6 >/dev/null 2>&1; then
    kquitapp6 plasmashell >/dev/null 2>&1 || true
  else
    pkill -x plasmashell >/dev/null 2>&1 || true
  fi

  sleep 1
  if command -v kstart >/dev/null 2>&1; then
    kstart plasmashell >/dev/null 2>&1 || true
  else
    plasmashell >/dev/null 2>&1 &
  fi
}

function duo-move-plasma-panels() {
  local mode="$1"
  local target_screen=""

  [[ "${MOVE_PLASMA_PANELS}" == true ]] || return 0
  command -v qdbus6 >/dev/null 2>&1 || return 0

  if [[ "${mode}" == "attached" ]]; then
    target_screen="${PLASMA_PANEL_SCREEN_ATTACHED}"
  else
    target_screen="${PLASMA_PANEL_SCREEN_DETACHED}"
  fi

  [[ "${target_screen}" =~ ^[0-9]+$ ]] || return 0

  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    "panels().forEach(function(panel){ panel.screen = ${target_screen}; });" >/dev/null 2>&1 || true
}

function duo-run-kscreen-doctor() {
  ${KSCREEN} "$@" >/dev/null 2>&1 || return 1
}

function duo-watch-display-backlight() {
  [[ "${SYNC_DISPLAY_BACKLIGHT}" == true ]] || return 0
  while true; do
    if [[ ! -e "${MAIN_BACKLIGHT_PATH}" ]]; then
      sleep 5
      continue
    fi
    inotifywait -e modify "${MAIN_BACKLIGHT_PATH}" >/dev/null 2>&1
    duo-sync-display-backlight
  done
}

function duo-apply-display-layout() {
  local mode=${1}
  [[ "${MANAGE_DISPLAY}" == true ]] || return 0

  if [[ -n "${KSCREEN}" ]]; then
    if [[ "${mode}" == "attached" ]]; then
      duo-run-kscreen-doctor "output.${MAIN_SCREEN}.enable" "output.${MAIN_SCREEN}.position.0,0" "output.${LOWER_SCREEN}.disable" || return 0
      duo-move-plasma-panels attached
      duo-refresh-plasma-shell
      duo-restart-plasma-shell
    else
      duo-run-kscreen-doctor "output.${MAIN_SCREEN}.enable" "output.${MAIN_SCREEN}.position.0,0" "output.${LOWER_SCREEN}.enable" "output.${LOWER_SCREEN}.position.${LOWER_POSITION}" || return 0
      duo-move-plasma-panels detached
      duo-refresh-plasma-shell
    fi
    return
  fi

  if [[ -n "${GDCTL}" ]]; then
    if [[ "${mode}" == "attached" ]]; then
      ${GDCTL} set --logical-monitor --primary --scale ${SCALE} --monitor "${MAIN_SCREEN}" --logical-monitor --scale ${SCALE} --monitor "${LOWER_SCREEN}" --off
    else
      ${GDCTL} set --logical-monitor --primary --scale ${SCALE} --monitor "${MAIN_SCREEN}" --logical-monitor --scale ${SCALE} --monitor "${LOWER_SCREEN}" --below "${MAIN_SCREEN}"
    fi
  fi
}

function duo-monitor-count() {
  if [[ -n "${KSCREEN}" ]]; then
    ${KSCREEN} -o 2>/dev/null | grep -c 'Output:' || true
    return
  fi
  if [[ -n "${GDCTL}" ]]; then
    ${GDCTL} show 2>/dev/null | grep -c 'Logical monitor #' || true
    return
  fi
  printf '0\n'
}

function duo-check-monitor() {
  KEYBOARD_ATTACHED=false
  if duo-has-keyboard-attached; then
    KEYBOARD_ATTACHED=true
  fi
  MONITOR_COUNT=$(duo-monitor-count)
  if [[ "${MANAGE_WIFI}" == true ]]; then
    WIFI_BEFORE=$(nmcli radio wifi 2>/dev/null || echo disabled)
  else
    WIFI_BEFORE=ignored
  fi
  if [[ "${MANAGE_BLUETOOTH}" == true ]]; then
    BLUETOOTH_BEFORE=$(rfkill -n -o SOFT list bluetooth 2>/dev/null | head -n1 || true)
  else
    BLUETOOTH_BEFORE=ignored
  fi
  duo-set-status

  if [[ "${KEYBOARD_ATTACHED}" == true ]]; then
    duo-set-kb-backlight "${BACKLIGHT_LEVEL}"
    duo-apply-display-layout attached
    if [[ "${MANAGE_WIFI}" == true && "${WIFI_BEFORE}" == "enabled" ]]; then
      nmcli radio wifi on 2>/dev/null || true
    fi
    if [[ "${MANAGE_BLUETOOTH}" == true ]]; then
      if [[ "${BLUETOOTH_BEFORE}" == "unblocked" ]]; then
        rfkill unblock bluetooth >/dev/null 2>&1 || true
      else
        rfkill block bluetooth >/dev/null 2>&1 || true
      fi
    fi
    if [[ -n "${NOTIFY_SEND}" ]]; then
      ${NOTIFY_SEND} -a "Zenbook Duo" -t 1000 --hint=int:transient:1 -i "preferences-desktop-display" "Keyboard attached: applying attached display layout"
    fi
  else
    duo-apply-display-layout detached
    if [[ "${MANAGE_WIFI}" == true ]]; then
      nmcli radio wifi on 2>/dev/null || true
    fi
    if [[ "${MANAGE_BLUETOOTH}" == true ]]; then
      rfkill unblock bluetooth >/dev/null 2>&1 || true
    fi
    if [[ -n "${NOTIFY_SEND}" ]]; then
      ${NOTIFY_SEND} -a "Zenbook Duo" -t 1000 --hint=int:transient:1 -i "preferences-desktop-display" "Keyboard detached: applying detached display layout"
    fi
  fi
}

function duo-watch-wifi() {
  [[ "${MANAGE_WIFI}" == true ]] || return 0
  if ! command -v gdbus >/dev/null 2>&1; then
    return
  fi
  gdbus monitor -y -d org.freedesktop.NetworkManager | grep --line-buffered WirelessEnabled | while read -r LINE; do
    sleep 1
    if [[ "${KEYBOARD_ATTACHED}" == true ]]; then
      if [[ "${LINE}" == *"<true>"* ]]; then
        WIFI_BEFORE=enabled
      else
        WIFI_BEFORE=disabled
      fi
      echo "$(date) - NETWORK - WIFI: ${WIFI_BEFORE}"
      duo-set-status
    fi
  done
}

function duo-watch-bluetooth() {
  [[ "${MANAGE_BLUETOOTH}" == true ]] || return 0
  if ! command -v gdbus >/dev/null 2>&1; then
    return
  fi
  gdbus monitor -y -d org.bluez | grep --line-buffered "'Powered':" | while read -r LINE; do
    sleep 1
    if [[ "${KEYBOARD_ATTACHED}" == true ]]; then
      if [[ "${LINE}" == *"<true>"* ]]; then
        BLUETOOTH_BEFORE=unblocked
      else
        BLUETOOTH_BEFORE=blocked
      fi
      echo "$(date) - NETWORK - Bluetooth: ${BLUETOOTH_BEFORE}"
      duo-set-status
    fi
  done
}

function duo-watch-monitor() {
  if command -v udevadm >/dev/null 2>&1; then
    udevadm monitor --subsystem-match=usb --udev --property | while read -r LINE; do
      if [[ "${LINE}" == ACTION=* ]]; then
        duo-check-monitor
      fi
    done
  else
    while inotifywait -e create,delete,modify /dev/bus/usb/* >/dev/null 2>&1; do
      duo-check-monitor
    done
  fi
}

function duo-watch-keyboard-bluetooth() {
  [[ -n "${BLUETOOTHCTL}" ]] || return 0
  if ! command -v gdbus >/dev/null 2>&1; then
    return 0
  fi

  gdbus monitor -y -d org.bluez | grep --line-buffered -E "Connected|InterfacesAdded|InterfacesRemoved" | while read -r _LINE; do
    sleep 1
    duo-check-monitor
  done
}

function duo-cli() {
  case "${1:-}" in
    pre|hibernate|shutdown)
      duo-set-kb-backlight 0
      ;;
    post|thaw|boot)
      duo-set-kb-backlight "${BACKLIGHT_LEVEL}"
      duo-check-monitor
      ;;
    kbb)
      duo-set-kb-backlight "${2:-${BACKLIGHT_LEVEL}}"
      ;;
    left-up)
      if [[ -n "${KSCREEN}" ]]; then
        ${KSCREEN} "output.${MAIN_SCREEN}.rotation.left" >/dev/null 2>&1 || true
      elif [[ -n "${GDCTL}" ]]; then
        ${GDCTL} set --logical-monitor --primary --scale ${SCALE} --monitor "${MAIN_SCREEN}" --transform 90
      fi
      ;;
    right-up)
      if [[ -n "${KSCREEN}" ]]; then
        ${KSCREEN} "output.${MAIN_SCREEN}.rotation.right" >/dev/null 2>&1 || true
      elif [[ -n "${GDCTL}" ]]; then
        ${GDCTL} set --logical-monitor --primary --scale ${SCALE} --monitor "${MAIN_SCREEN}" --transform 270
      fi
      ;;
    bottom-up)
      if [[ -n "${KSCREEN}" ]]; then
        ${KSCREEN} "output.${MAIN_SCREEN}.rotation.inverted" >/dev/null 2>&1 || true
      elif [[ -n "${GDCTL}" ]]; then
        ${GDCTL} set --logical-monitor --primary --scale ${SCALE} --monitor "${MAIN_SCREEN}" --transform 180
      fi
      ;;
    normal)
      if [[ -n "${KSCREEN}" ]]; then
        ${KSCREEN} "output.${MAIN_SCREEN}.rotation.normal" >/dev/null 2>&1 || true
      elif [[ -n "${GDCTL}" ]]; then
        ${GDCTL} set --logical-monitor --primary --scale ${SCALE} --monitor "${MAIN_SCREEN}"
      fi
      ;;
    install-backlight-helper)
      duo-write-backlight-script "${BACKLIGHT_PY_SYSTEM}"
      ;;
    version|--version|-V)
      echo "zenbook-duo-systools-fnkeys ${HELPER_VERSION}"
      ;;
    *)
      echo "Unknown command: $*"
      ;;
  esac
}

function main() {
  duo-set-kb-backlight "${BACKLIGHT_LEVEL}"
  duo-check-monitor
  duo-watch-monitor &
  duo-watch-keyboard-bluetooth &
  duo-watch-display-backlight &
  duo-watch-wifi &
  duo-watch-bluetooth &
  wait
}

if [[ -z "${1:-}" ]]; then
  main
else
  duo-cli "$@"
fi
