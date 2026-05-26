#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/zenbook-duo/fnkeys.conf"
HELPER_VERSION="1.1"
TMP_DIR="/tmp/duo"
BACKLIGHT_PY_SYSTEM="/usr/lib/zenbook-duo-fnkeys/backlight.py"
INPUT_WATCHER_SYSTEM="/usr/lib/zenbook-duo-fnkeys/input_watcher.py"
DEFAULT_BACKLIGHT=2
DEFAULT_SCALE=1
DEFAULT_MAIN_SCREEN="eDP-1"
DEFAULT_LOWER_SCREEN="eDP-2"
DEFAULT_MAIN_BACKLIGHT="/sys/class/backlight/intel_backlight/brightness"
DEFAULT_LOWER_BACKLIGHT="/sys/class/backlight/card1-eDP-2-backlight/brightness"
DEFAULT_KEYBOARD_USB_MATCH="Primax|ASUS.*Keyboard|ASUSTeK.*Keyboard|Zenbook Duo.*Keyboard|0b05:1b2[cd]"
DEFAULT_KEYBOARD_DOCK_USB_PATH="3-6"
DEFAULT_KEYBOARD_BT_MAC="E9:C7:F1:96:05:3C"
DEFAULT_KEYBOARD_BT_NAME="ASUS Zenbook Duo Keyboard"
DEFAULT_KEYBOARD_BT_ADAPTER="hci0"
DEFAULT_KEYBOARD_BT_GATT_CHAR="service001b/char003b"
DEFAULT_BACKLIGHT_UP_VALUE=16
DEFAULT_BACKLIGHT_DOWN_VALUE=199
DEFAULT_DISPLAY_BRIGHTNESS_STEP=20
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
KEYBOARD_BT_ADAPTER="${FNKEYS_KEYBOARD_BT_ADAPTER:-$DEFAULT_KEYBOARD_BT_ADAPTER}"
KEYBOARD_BT_GATT_CHAR="${FNKEYS_KEYBOARD_BT_GATT_CHAR:-$DEFAULT_KEYBOARD_BT_GATT_CHAR}"
KEYBOARD_BT_CHAR_PATH="${FNKEYS_KEYBOARD_BT_CHAR_PATH:-}"
BACKLIGHT_INPUT_WATCH="${FNKEYS_BACKLIGHT_INPUT_WATCH:-true}"
BACKLIGHT_UP_VALUE="${FNKEYS_BACKLIGHT_UP_VALUE:-$DEFAULT_BACKLIGHT_UP_VALUE}"
BACKLIGHT_DOWN_VALUE="${FNKEYS_BACKLIGHT_DOWN_VALUE:-$DEFAULT_BACKLIGHT_DOWN_VALUE}"
BACKLIGHT_EVENT_CODE="${FNKEYS_BACKLIGHT_EVENT_CODE:-ABS_MISC}"
BACKLIGHT_STATE_FILE="${FNKEYS_BACKLIGHT_STATE_FILE:-${TMP_DIR}/kb-backlight-level}"
BACKLIGHT_EVENT_DEBOUNCE_SECONDS="${FNKEYS_BACKLIGHT_EVENT_DEBOUNCE_SECONDS:-0.15}"
DISPLAY_BRIGHTNESS_STEP="${FNKEYS_DISPLAY_BRIGHTNESS_STEP:-$DEFAULT_DISPLAY_BRIGHTNESS_STEP}"
LOWER_POSITION="${FNKEYS_LOWER_POSITION:-$DEFAULT_LOWER_POSITION}"
MANAGE_DISPLAY="${FNKEYS_MANAGE_DISPLAY:-true}"
MANAGE_WIFI="${FNKEYS_MANAGE_WIFI:-false}"
MANAGE_BLUETOOTH="${FNKEYS_MANAGE_BLUETOOTH:-false}"
KEEP_BLUETOOTH_ON_WHEN_ATTACHED="${FNKEYS_KEEP_BLUETOOTH_ON_WHEN_ATTACHED:-true}"
RESPECT_BLUETOOTH_FORCED_OFF="${FNKEYS_RESPECT_BLUETOOTH_FORCED_OFF:-true}"
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
  install -Dm755 "$(dirname "${BASH_SOURCE[0]}")/backlight.py" "${dest}" 2>/dev/null || cat > "${dest}" <<'PY'
#!/usr/bin/env python3
import os
import subprocess
import sys

import usb.core
import usb.util

REPORT_ID = 0x5A
WVALUE = 0x035A
WINDEX = 4
WLENGTH = 16
PAYLOAD = (0xBA, 0xC5, 0xC4)
BLUEZ_MAIN_CONF = '/etc/bluetooth/main.conf'


def parse_level(value):
    level = int(value)
    if level < 0 or level > 3:
        raise ValueError
    return level


def set_usb_backlight(vendor_id, product_id, level):
    packet = [0] * WLENGTH
    packet[0] = REPORT_ID
    packet[1:4] = PAYLOAD
    packet[4] = level
    dev = usb.core.find(idVendor=int(vendor_id, 16), idProduct=int(product_id, 16))
    if dev is None:
        sys.exit(1)
    reattached = False
    try:
        if dev.is_kernel_driver_active(WINDEX):
            dev.detach_kernel_driver(WINDEX)
            reattached = True
    except Exception:
        pass
    try:
        ret = dev.ctrl_transfer(0x21, 0x09, WVALUE, WINDEX, packet, timeout=1000)
        sys.exit(0 if ret == WLENGTH else 1)
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


def set_bluetooth_backlight(characteristic_path, level):
    if not bluez_exports_claimed_services_read_write():
        sys.exit(1)

    write_value = ' '.join(f'0x{byte:02x}' for byte in (*PAYLOAD, level))
    commands = (
        f'gatt.select-attribute {characteristic_path}\n'
        f'gatt.write "{write_value}"\n'
        'quit\n'
    )
    result = subprocess.run(
        ['bluetoothctl'],
        check=False,
        text=True,
        input=commands,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output = '\n'.join(part for part in (result.stdout.strip(), result.stderr.strip()) if part)
    if result.returncode != 0 or 'Failed' in output or 'Error' in output or 'not available' in output:
        sys.exit(result.returncode or 1)
    sys.exit(0 if 'Attempting to write' in output else 1)


def bluez_exports_claimed_services_read_write():
    try:
        with open(BLUEZ_MAIN_CONF, encoding='utf-8') as config:
            in_gatt = False
            for raw_line in config:
                line = raw_line.strip()
                if not line or line.startswith('#'):
                    continue
                if line.startswith('[') and line.endswith(']'):
                    in_gatt = line.lower() == '[gatt]'
                    continue
                if in_gatt and line.lower().replace(' ', '') == 'exportclaimedservices=read-write':
                    return True
    except OSError:
        return False
    return False


if __name__ == '__main__':
    if len(sys.argv) == 2:
        vendor = os.environ.get('DUO_VENDOR_ID', '0')
        product = os.environ.get('DUO_PRODUCT_ID', '0')
        set_usb_backlight(vendor, product, parse_level(sys.argv[1]))
    if len(sys.argv) == 5 and sys.argv[1] == 'usb':
        set_usb_backlight(sys.argv[2], sys.argv[3], parse_level(sys.argv[4]))
    if len(sys.argv) == 4 and sys.argv[1] == 'bluetooth':
        set_bluetooth_backlight(sys.argv[2], parse_level(sys.argv[3]))
    sys.exit(1)
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

function duo-keyboard-bluetooth-char-path() {
  if [[ -n "${KEYBOARD_BT_CHAR_PATH}" ]]; then
    printf '%s' "${KEYBOARD_BT_CHAR_PATH}"
    return 0
  fi

  [[ -n "${KEYBOARD_BT_MAC}" ]] || return 1
  [[ -n "${KEYBOARD_BT_ADAPTER}" ]] || return 1
  [[ -n "${KEYBOARD_BT_GATT_CHAR}" ]] || return 1

  local mac_path="${KEYBOARD_BT_MAC//:/_}"
  printf '/org/bluez/%s/dev_%s/%s' "${KEYBOARD_BT_ADAPTER}" "${mac_path}" "${KEYBOARD_BT_GATT_CHAR}"
}

function duo-bluetooth-forced-off() {
  [[ "${RESPECT_BLUETOOTH_FORCED_OFF}" == true ]] || return 1
  [[ "$(rfkill -n -o SOFT list bluetooth 2>/dev/null | head -n1 || true)" == "blocked" ]]
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

function duo-unblock-bluetooth-if-allowed() {
  if duo-bluetooth-forced-off; then
    echo "$(date) - NETWORK - Bluetooth is blocked by user; using dock USB fallback only."
    return 0
  fi

  rfkill unblock bluetooth >/dev/null 2>&1 || true
}

function duo-notify-keyboard-mode() {
  local mode="${1}"
  local message="${2}"
  local state_file="${TMP_DIR}/last-notified-keyboard-mode"
  local last_mode=""

  [[ -n "${NOTIFY_SEND}" ]] || return 0
  [[ -r "${state_file}" ]] && last_mode="$(<"${state_file}")"
  [[ "${last_mode}" != "${mode}" ]] || return 0

  printf '%s' "${mode}" >"${state_file}"
  ${NOTIFY_SEND} -a "Zenbook Duo" -t 1000 --hint=int:transient:1 -i "preferences-desktop-display" "${message}" || true
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
  local source_dir
  source_dir="$(dirname "${BASH_SOURCE[0]}")"

  if [[ -x "${source_dir}/backlight.py" ]]; then
    printf '%s' "${source_dir}/backlight.py"
    return
  fi

  if [[ ! -x "${path}" ]]; then
    path="${TMP_DIR}/backlight.py"
    if [[ ! -f "${path}" ]]; then
      duo-write-backlight-script "${path}"
    fi
  fi
  printf '%s' "${path}"
}

function duo-ensure-input-watcher-script() {
  local path="${INPUT_WATCHER_SYSTEM}"
  local source_dir
  source_dir="$(dirname "${BASH_SOURCE[0]}")"

  if [[ -x "${source_dir}/input_watcher.py" ]]; then
    printf '%s' "${source_dir}/input_watcher.py"
    return
  fi

  if [[ -x "${path}" ]]; then
    printf '%s' "${path}"
    return
  fi

  return 1
}

function duo-write-backlight-state() {
  local state_dir
  state_dir="$(dirname "${BACKLIGHT_STATE_FILE}")"
  [[ -z "${state_dir}" || "${state_dir}" == "." ]] || mkdir -p "${state_dir}"
  printf '%s' "${1}" >"${BACKLIGHT_STATE_FILE}"
}

function duo-read-backlight-state() {
  local value
  value="$(cat "${BACKLIGHT_STATE_FILE}" 2>/dev/null || true)"
  if [[ "${value}" =~ ^[0-3]$ ]]; then
    printf '%s' "${value}"
    return
  fi
  duo-normalize-backlight-level "${BACKLIGHT_LEVEL}"
}

function duo-normalize-backlight-level() {
  local value="${1}"
  if [[ ! "${value}" =~ ^[0-3]$ ]]; then
    echo "Invalid keyboard backlight level: ${value}. Expected 0, 1, 2, or 3." >&2
    return 1
  fi
  printf '%s' "${value}"
}

function duo-cycle-kb-backlight() {
  local current next
  current="$(duo-read-backlight-state)"
  next=$(( (current + 1) % 4 ))
  duo-set-kb-backlight "${next}"
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
    duo-write-backlight-state "${target}"
    return
  fi

  if [[ -z "${PYTHON3}" ]]; then
    echo "Warning: python3 is not available for USB backlight control."
    return 1
  fi

  local keyboard_id vendor product backlight_script
  keyboard_id=$(duo-find-keyboard-usb)
  backlight_script=$(duo-ensure-backlight-script)

  if [[ -n "${keyboard_id}" ]]; then
    vendor=${keyboard_id%:*}
    product=${keyboard_id#*:}
    if sudo "${PYTHON3}" "${backlight_script}" usb "0x${vendor}" "0x${product}" "${target}" >/dev/null 2>&1; then
      duo-write-backlight-state "${target}"
      return 0
    fi
  fi

  if duo-has-keyboard-bluetooth; then
    local bt_char_path
    bt_char_path="$(duo-keyboard-bluetooth-char-path || true)"
    if [[ -n "${bt_char_path}" ]] && "${PYTHON3}" "${backlight_script}" bluetooth "${bt_char_path}" "${target}" >/dev/null 2>&1; then
      duo-write-backlight-state "${target}"
      return 0
    fi
  fi

  if [[ -z "${keyboard_id}" ]]; then
    echo "No Zenbook Duo keyboard device found for USB or Bluetooth backlight control."
  else
    echo "Zenbook Duo keyboard backlight control failed over USB and Bluetooth."
  fi
  return 1
}

function duo-normalize-display-brightness-step() {
  local value="${1}"
  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "Invalid display brightness step: ${value}. Expected 1-100." >&2
    return 1
  fi
  if (( value < 1 || value > 100 )); then
    echo "Invalid display brightness step: ${value}. Expected 1-100." >&2
    return 1
  fi
  printf '%s' "${value}"
}

function duo-read-display-brightness-percent() {
  local path="${1}"
  local max current

  [[ -r "${path}" ]] || return 1
  max="$(cat "${path%/*}/max_brightness" 2>/dev/null || true)"
  current="$(cat "${path}" 2>/dev/null || true)"

  if [[ ! "${max}" =~ ^[0-9]+$ || "${max}" -le 0 || ! "${current}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  printf '%s' "$(( (current * 100 + max / 2) / max ))"
}

function duo-write-display-brightness-percent() {
  local path="${1}"
  local percent="${2}"
  local max brightness

  [[ -e "${path}" ]] || return 0
  max="$(cat "${path%/*}/max_brightness" 2>/dev/null || true)"
  if [[ ! "${max}" =~ ^[0-9]+$ || "${max}" -le 0 ]]; then
    return 1
  fi

  brightness=$(( max * percent / 100 ))
  if (( percent > 0 && brightness < 1 )); then
    brightness=1
  fi
  if (( brightness > max )); then
    brightness=${max}
  fi

  if [[ -w "${path}" ]]; then
    printf '%s' "${brightness}" >"${path}"
  else
    printf '%s' "${brightness}" | sudo ${TEE} "${path}" >/dev/null
  fi
}

function duo-cycle-display-brightness() {
  local step current next

  step="$(duo-normalize-display-brightness-step "${DISPLAY_BRIGHTNESS_STEP}")"
  current="$(duo-read-display-brightness-percent "${MAIN_BACKLIGHT_PATH}" || true)"
  if [[ ! "${current}" =~ ^[0-9]+$ ]]; then
    current=0
  fi

  if (( current >= 100 )); then
    next="${step}"
  else
    next=$(( ((current / step) + 1) * step ))
    if (( next > 100 )); then
      next=100
    fi
  fi

  duo-write-display-brightness-percent "${MAIN_BACKLIGHT_PATH}" "${next}"
  duo-write-display-brightness-percent "${LOWER_BACKLIGHT_PATH}" "${next}"
}

function duo-set-kb-backlight-retry() {
  local level="${1}"
  local attempts="${2:-12}"
  local delay="${3:-1}"
  local lock_dir="${TMP_DIR}/kb-backlight-retry.lock"
  local attempt

  if ! mkdir "${lock_dir}" 2>/dev/null; then
    return 0
  fi

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if duo-set-kb-backlight "${level}"; then
      rmdir "${lock_dir}" 2>/dev/null || true
      return 0
    fi
    sleep "${delay}"
  done

  rmdir "${lock_dir}" 2>/dev/null || true
  return 1
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
    duo-set-kb-backlight "${BACKLIGHT_LEVEL}" || true
    duo-apply-display-layout attached
    if [[ "${MANAGE_WIFI}" == true && "${WIFI_BEFORE}" == "enabled" ]]; then
      nmcli radio wifi on 2>/dev/null || true
    fi
    if [[ "${MANAGE_BLUETOOTH}" == true ]]; then
      if [[ "${KEEP_BLUETOOTH_ON_WHEN_ATTACHED}" == true ]]; then
        duo-unblock-bluetooth-if-allowed
      elif [[ "${BLUETOOTH_BEFORE}" == "unblocked" ]]; then
        duo-unblock-bluetooth-if-allowed
      else
        rfkill block bluetooth >/dev/null 2>&1 || true
      fi
    fi
    duo-notify-keyboard-mode attached "Keyboard attached: applying attached display layout"
  else
    duo-apply-display-layout detached
    if [[ "${MANAGE_WIFI}" == true ]]; then
      nmcli radio wifi on 2>/dev/null || true
    fi
    if [[ "${MANAGE_BLUETOOTH}" == true ]]; then
      duo-unblock-bluetooth-if-allowed
    fi
    duo-set-kb-backlight-retry "${BACKLIGHT_LEVEL}" 12 1 &
    duo-notify-keyboard-mode detached "Keyboard detached: applying detached display layout"
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

function duo-current-keyboard-mode() {
  if duo-has-keyboard-attached; then
    printf 'attached'
  else
    printf 'detached'
  fi
}

function duo-watch-keyboard-state-poll() {
  local last_mode current_mode

  last_mode="$(duo-current-keyboard-mode)"
  while true; do
    sleep 2
    current_mode="$(duo-current-keyboard-mode)"
    if [[ "${current_mode}" != "${last_mode}" ]]; then
      duo-check-monitor
      last_mode="${current_mode}"
    fi
  done
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

function duo-watch-keyboard-backlight-input() {
  [[ "${BACKLIGHT_INPUT_WATCH}" == true ]] || return 0
  [[ -n "${PYTHON3}" ]] || return 0

  local input_watcher
  input_watcher="$(duo-ensure-input-watcher-script || true)"
  [[ -n "${input_watcher}" ]] || return 0

  FNKEYS_KEYBOARD_INPUT_NAME="${KEYBOARD_BT_NAME}" \
  FNKEYS_BACKLIGHT_EVENT_CODE="${BACKLIGHT_EVENT_CODE}" \
  FNKEYS_BACKLIGHT_UP_VALUE="${BACKLIGHT_UP_VALUE}" \
  FNKEYS_BACKLIGHT_DOWN_VALUE="${BACKLIGHT_DOWN_VALUE}" \
  FNKEYS_BACKLIGHT_EVENT_DEBOUNCE_SECONDS="${BACKLIGHT_EVENT_DEBOUNCE_SECONDS}" \
  FNKEYS_HELPER="${BASH_SOURCE[0]}" \
    "${PYTHON3}" "${input_watcher}"
}

function duo-cli() {
  case "${1:-}" in
    pre|hibernate|shutdown)
      duo-set-kb-backlight 0 || true
      ;;
    post|thaw|boot)
      duo-set-kb-backlight "${BACKLIGHT_LEVEL}" || true
      duo-check-monitor
      ;;
    kbb)
      duo-set-kb-backlight "${2:-${BACKLIGHT_LEVEL}}"
      ;;
    kbb-cycle)
      duo-cycle-kb-backlight
      ;;
    display-brightness-cycle)
      duo-cycle-display-brightness
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
  duo-set-kb-backlight "${BACKLIGHT_LEVEL}" || true
  duo-check-monitor
  duo-watch-monitor &
  duo-watch-keyboard-state-poll &
  duo-watch-keyboard-bluetooth &
  duo-watch-keyboard-backlight-input &
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
