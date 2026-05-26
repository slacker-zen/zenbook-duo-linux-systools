#!/usr/bin/env bash
set -euo pipefail

SYS_CONFIG_FILE="/etc/zenbook-duo/duo-sysstates.conf"
FN_CONFIG_FILE="/etc/zenbook-duo/fnkeys.conf"
HELPER_VERSION="1.0"

MAIN_HELPER="${ZENBOOK_DUO_SYSTOOLS:-/usr/bin/zenbook-duo-systools}"
FNKEYS_HELPER="${ZENBOOK_DUO_FNKEYS:-/usr/bin/zenbook-duo-systools-fnkeys}"
INPUT_WATCHER_SYSTEM="/usr/lib/zenbook-duo-fnkeys/input_watcher.py"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/zenbook-duo"
EVENT_FIFO="${STATE_DIR}/matrix-events"
STATE_FILE="${STATE_DIR}/matrix-state"

KEYBOARD_USB_MATCH="Primax|ASUS.*Keyboard|ASUSTeK.*Keyboard|Zenbook Duo.*Keyboard|0b05:1b2[cd]"
KEYBOARD_DOCK_USB_PATH="3-6"
KEYBOARD_BT_MAC="E9:C7:F1:96:05:3C"
KEYBOARD_BT_NAME="ASUS Zenbook Duo Keyboard"
KEYBOARD_BT_ADAPTER="hci0"
BACKLIGHT_LEVEL=2
BACKLIGHT_INPUT_WATCH=true
BACKLIGHT_INPUT_TRANSPORTS="bluetooth"
BACKLIGHT_UP_VALUE=16
BACKLIGHT_DOWN_VALUE=199
BACKLIGHT_EVENT_CODE="ABS_MISC"
BACKLIGHT_EVENT_DEBOUNCE_SECONDS=0.15
MANAGE_DISPLAY=true
APPLY_KEYBOARD_BACKLIGHT=true
WATCH_BLUETOOTH=true
WATCH_USB=true
POLL_INTERVAL_SECONDS=5

PYTHON3="$(command -v python3 || true)"
BLUETOOTHCTL="$(command -v bluetoothctl || true)"
INPUT_WATCHER_PID=""

mkdir -p "${STATE_DIR}"

log() {
  printf '[zenbook-duo-matrix] %s\n' "$*"
}

load_config() {
  if [[ -f "${SYS_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${SYS_CONFIG_FILE}"
  fi
  if [[ -f "${FN_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${FN_CONFIG_FILE}"
  fi

  KEYBOARD_USB_MATCH="${FNKEYS_KEYBOARD_USB_MATCH:-${KEYBOARD_USB_MATCH}}"
  KEYBOARD_DOCK_USB_PATH="${FNKEYS_KEYBOARD_DOCK_USB_PATH:-${KEYBOARD_DOCK_USB_PATH}}"
  KEYBOARD_BT_MAC="${FNKEYS_KEYBOARD_BT_MAC:-${KEYBOARD_BT_MAC}}"
  KEYBOARD_BT_NAME="${FNKEYS_KEYBOARD_BT_NAME:-${KEYBOARD_BT_NAME}}"
  KEYBOARD_BT_ADAPTER="${FNKEYS_KEYBOARD_BT_ADAPTER:-${KEYBOARD_BT_ADAPTER}}"
  BACKLIGHT_LEVEL="${FNKEYS_BACKLIGHT_LEVEL:-${BACKLIGHT_LEVEL}}"
  BACKLIGHT_INPUT_WATCH="${FNKEYS_BACKLIGHT_INPUT_WATCH:-${BACKLIGHT_INPUT_WATCH}}"
  BACKLIGHT_INPUT_TRANSPORTS="${FNKEYS_BACKLIGHT_INPUT_TRANSPORTS:-${BACKLIGHT_INPUT_TRANSPORTS}}"
  BACKLIGHT_UP_VALUE="${FNKEYS_BACKLIGHT_UP_VALUE:-${BACKLIGHT_UP_VALUE}}"
  BACKLIGHT_DOWN_VALUE="${FNKEYS_BACKLIGHT_DOWN_VALUE:-${BACKLIGHT_DOWN_VALUE}}"
  BACKLIGHT_EVENT_CODE="${FNKEYS_BACKLIGHT_EVENT_CODE:-${BACKLIGHT_EVENT_CODE}}"
  BACKLIGHT_EVENT_DEBOUNCE_SECONDS="${FNKEYS_BACKLIGHT_EVENT_DEBOUNCE_SECONDS:-${BACKLIGHT_EVENT_DEBOUNCE_SECONDS}}"
  MANAGE_DISPLAY="${ZENBOOK_DUO_MATRIX_MANAGE_DISPLAY:-${FNKEYS_MANAGE_DISPLAY:-${MANAGE_DISPLAY_LAYOUT:-${MANAGE_DISPLAY}}}}"
  APPLY_KEYBOARD_BACKLIGHT="${ZENBOOK_DUO_MATRIX_APPLY_KEYBOARD_BACKLIGHT:-${APPLY_KEYBOARD_BACKLIGHT}}"
  WATCH_BLUETOOTH="${ZENBOOK_DUO_MATRIX_WATCH_BLUETOOTH:-${WATCH_BLUETOOTH}}"
  WATCH_USB="${ZENBOOK_DUO_MATRIX_WATCH_USB:-${WATCH_USB}}"
  POLL_INTERVAL_SECONDS="${ZENBOOK_DUO_MATRIX_POLL_INTERVAL_SECONDS:-${POLL_INTERVAL_SECONDS}}"
}

emit_event() {
  local event="${1}"
  if [[ -p "${EVENT_FIFO}" ]]; then
    printf '%s\n' "${event}" >"${EVENT_FIFO}" 2>/dev/null || true
  fi
}

usb_device_matches_keyboard() {
  local device="$1"
  local product="" manufacturer="" vendor="" product_id="" devpath="" haystack=""

  [[ -r "${device}/product" ]] && product="$(<"${device}/product")"
  [[ -r "${device}/manufacturer" ]] && manufacturer="$(<"${device}/manufacturer")"
  [[ -r "${device}/idVendor" ]] && vendor="$(<"${device}/idVendor")"
  [[ -r "${device}/idProduct" ]] && product_id="$(<"${device}/idProduct")"
  [[ -r "${device}/devpath" ]] && devpath="$(<"${device}/devpath")"

  haystack="${device##*/} ${devpath} ${manufacturer} ${product} ${vendor}:${product_id}"
  [[ "${haystack}" =~ ${KEYBOARD_USB_MATCH} ]]
}

usb_device_matches_dock_path() {
  local device="$1"
  local devpath="" haystack=""

  [[ -n "${KEYBOARD_DOCK_USB_PATH}" ]] || return 1
  usb_device_matches_keyboard "${device}" || return 1
  [[ -r "${device}/devpath" ]] && devpath="$(<"${device}/devpath")"
  haystack="${device##*/} ${devpath}"
  [[ "${haystack}" =~ ${KEYBOARD_DOCK_USB_PATH} ]]
}

keyboard_attached() {
  local usb_device
  for usb_device in /sys/bus/usb/devices/*; do
    [[ -d "${usb_device}" ]] || continue
    if usb_device_matches_dock_path "${usb_device}"; then
      return 0
    fi
  done
  return 1
}

keyboard_usb_present() {
  local usb_device
  for usb_device in /sys/bus/usb/devices/*; do
    [[ -d "${usb_device}" ]] || continue
    if usb_device_matches_keyboard "${usb_device}"; then
      return 0
    fi
  done
  return 1
}

keyboard_bluetooth_connected() {
  [[ -n "${BLUETOOTHCTL}" ]] || return 1
  [[ -n "${KEYBOARD_BT_MAC}" ]] || return 1
  "${BLUETOOTHCTL}" info "${KEYBOARD_BT_MAC}" 2>/dev/null | grep -q "Connected: yes"
}

derive_state() {
  local physical_mode="detached"
  local transport="absent"
  local bt_connected="false"
  local usb_present="false"

  if keyboard_attached; then
    physical_mode="attached"
  fi
  if keyboard_usb_present; then
    usb_present="true"
  fi
  if keyboard_bluetooth_connected; then
    bt_connected="true"
  fi

  if [[ "${physical_mode}" == "attached" ]]; then
    transport="dock_usb"
  elif [[ "${usb_present}" == "true" ]]; then
    transport="cradle_usb"
  elif [[ "${bt_connected}" == "true" ]]; then
    transport="bluetooth"
  fi

  printf 'physical_mode=%s\ntransport=%s\nusb_present=%s\nbt_connected=%s\n' \
    "${physical_mode}" "${transport}" "${usb_present}" "${bt_connected}"
}

state_value() {
  local state="$1"
  local key="$2"
  printf '%s\n' "${state}" | awk -F= -v key="${key}" '$1 == key { print $2; exit }'
}

load_last_state() {
  [[ -r "${STATE_FILE}" ]] && cat "${STATE_FILE}" || true
}

save_state() {
  printf '%s\n' "${1}" >"${STATE_FILE}"
}

apply_display_mode() {
  local mode="$1"
  [[ "${MANAGE_DISPLAY}" == true ]] || return 0
  [[ -x "${MAIN_HELPER}" ]] || return 0
  "${MAIN_HELPER}" display "${mode}" || true
}

apply_keyboard_backlight() {
  [[ "${APPLY_KEYBOARD_BACKLIGHT}" == true ]] || return 0
  [[ -x "${FNKEYS_HELPER}" ]] || return 0
  "${FNKEYS_HELPER}" kbb "${BACKLIGHT_LEVEL}" || true
}

transport_in_list() {
  local needle="$1"
  local item
  local IFS=', '

  for item in ${BACKLIGHT_INPUT_TRANSPORTS}; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

input_watcher_running() {
  [[ -n "${INPUT_WATCHER_PID}" ]] || return 1
  kill -0 "${INPUT_WATCHER_PID}" >/dev/null 2>&1
}

start_input_watcher() {
  [[ "${BACKLIGHT_INPUT_WATCH}" == true ]] || return 0
  [[ -n "${PYTHON3}" ]] || return 0
  [[ -x "${INPUT_WATCHER_SYSTEM}" ]] || return 0

  if input_watcher_running; then
    return 0
  fi

  FNKEYS_KEYBOARD_INPUT_NAME="${KEYBOARD_BT_NAME}" \
  FNKEYS_KEYBOARD_INPUT_NAME_REGEX="(ASUS|Primax).*Zenbook Duo Keyboard" \
  FNKEYS_BACKLIGHT_EVENT_CODE="${BACKLIGHT_EVENT_CODE}" \
  FNKEYS_BACKLIGHT_UP_VALUE="${BACKLIGHT_UP_VALUE}" \
  FNKEYS_BACKLIGHT_DOWN_VALUE="${BACKLIGHT_DOWN_VALUE}" \
  FNKEYS_BACKLIGHT_EVENT_DEBOUNCE_SECONDS="${BACKLIGHT_EVENT_DEBOUNCE_SECONDS}" \
  FNKEYS_HELPER="${FNKEYS_HELPER}" \
    "${PYTHON3}" "${INPUT_WATCHER_SYSTEM}" &
  INPUT_WATCHER_PID="$!"
  log "Started physical Fn-key input watcher for transports: ${BACKLIGHT_INPUT_TRANSPORTS}"
}

stop_input_watcher() {
  if input_watcher_running; then
    kill "${INPUT_WATCHER_PID}" >/dev/null 2>&1 || true
    wait "${INPUT_WATCHER_PID}" 2>/dev/null || true
    log "Stopped physical Fn-key input watcher"
  fi
  INPUT_WATCHER_PID=""
}

reconcile_input_watcher() {
  local transport="$1"

  if transport_in_list "${transport}"; then
    start_input_watcher
  else
    stop_input_watcher
  fi
}

reconcile() {
  local reason="${1:-event}"
  local current previous current_mode previous_mode current_transport previous_transport

  current="$(derive_state)"
  previous="$(load_last_state)"
  current_mode="$(state_value "${current}" physical_mode)"
  previous_mode="$(state_value "${previous}" physical_mode)"
  current_transport="$(state_value "${current}" transport)"
  previous_transport="$(state_value "${previous}" transport)"

  reconcile_input_watcher "${current_transport}"

  if [[ "${current}" == "${previous}" ]]; then
    return 0
  fi

  log "State changed (${reason}): mode ${previous_mode:-unknown}->${current_mode}, transport ${previous_transport:-unknown}->${current_transport}"
  save_state "${current}"

  if [[ "${current_mode}" != "${previous_mode}" ]]; then
    apply_display_mode "${current_mode}"
  fi

  if [[ "${current_transport}" != "${previous_transport}" && "${current_transport}" != "absent" ]]; then
    apply_keyboard_backlight
  fi

}

watch_usb() {
  [[ "${WATCH_USB}" == true ]] || return 0
  command -v udevadm >/dev/null 2>&1 || return 0

  udevadm monitor --subsystem-match=usb --udev --property | while IFS= read -r line; do
    if [[ "${line}" == ACTION=* ]]; then
      emit_event usb
    fi
  done
}

watch_bluetooth() {
  [[ "${WATCH_BLUETOOTH}" == true ]] || return 0
  command -v gdbus >/dev/null 2>&1 || return 0

  gdbus monitor -y -d org.bluez | grep --line-buffered -E "Connected|InterfacesAdded|InterfacesRemoved" | while IFS= read -r _line; do
    emit_event bluetooth
  done
}

watch_poll() {
  while sleep "${POLL_INTERVAL_SECONDS}"; do
    emit_event poll
  done
}

stop_children() {
  trap - INT TERM EXIT
  stop_input_watcher
  pkill -P $$ >/dev/null 2>&1 || true
  rm -f "${EVENT_FIFO}"
}

run_service() {
  rm -f "${EVENT_FIFO}"
  mkfifo "${EVENT_FIFO}"
  trap stop_children INT TERM EXIT
  exec 3<>"${EVENT_FIFO}"

  reconcile startup
  watch_usb &
  watch_bluetooth &
  watch_poll &

  while IFS= read -r event; do
    reconcile "${event}"
  done <&3
}

usage() {
  cat <<EOF
Usage: $0 <action>

Actions:
  service        Run the event-driven matrix coordinator
  reconcile      Reconcile state once
  status         Print derived state
  version        Show version
EOF
}

main() {
  load_config

  case "${1:-service}" in
    service)
      run_service
      ;;
    reconcile)
      reconcile manual
      ;;
    status)
      derive_state
      ;;
    version|--version|-V)
      echo "zenbook-duo-matrix ${HELPER_VERSION}"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
