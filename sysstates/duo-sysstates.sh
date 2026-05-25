#!/usr/bin/env bash
set -euo pipefail

# Zenbook Pro Duo / Duo LED new handler
# Supports:
# - keyboard attached/detached modes
# - screen rotation states: normal, left, right, inverted
# - display layout switching with kscreen-doctor or xrandr fallback
# - keyboard backlight level
# - power profile selection for AC vs battery

CONFIG_FILE="/etc/zenbook-duo/duo-sysstates.conf"
HELPER_VERSION="1.1"

# Default values, override in config file
LOWER_SCREEN="eDP-2"
MAIN_SCREEN="eDP-1"
MAIN_ROTATION="normal"
LOWER_ROTATION="normal"
LOWER_POSITION="0,1200"
KEYBOARD_MATCH="Primax|ASUS.*Zenbook Duo.*Keyboard|Zenbook Duo.*Keyboard"
KEYBOARD_USB_MATCH="Primax|ASUS.*Keyboard|ASUSTeK.*Keyboard|Zenbook Duo.*Keyboard|0b05:1b2[cd]"
KEYBOARD_DOCK_USB_PATH="3-6"
KEYBOARD_BT_MAC="E9:C7:F1:96:05:3C"
KEYBOARD_BT_NAME="ASUS Zenbook Duo Keyboard"
BACKLIGHT_LEVEL_PERCENT=50
FNKEYS_HELPER="/usr/bin/zenbook-duo-systools-fnkeys"
MANAGE_DISPLAY_LAYOUT=false
MOVE_WINDOWS_TO_MAIN=false
REFRESH_PLASMA_ON_LAYOUT=false
RESTART_PLASMA_ON_ATTACH=false
WATCH_DEBOUNCE_SECONDS=1
MOVE_PLASMA_PANELS=true
PLASMA_PANEL_SCREEN_ATTACHED=0
PLASMA_PANEL_SCREEN_DETACHED=1
LID_STATE_PATH="auto"
LID_WATCH_INTERVAL_SECONDS=1

SUPPORTED_ROTATIONS=(normal left right inverted)

log() {
  printf '[zenbook-duo-systools] %s\n' "$*"
}

load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
  fi
}

usb_device_matches_dock_path() {
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

keyboard_attached() {
  # Attached means docked through the built-in keyboard connector. Bluetooth
  # and ordinary wired USB both leave the lower screen physically uncovered.
  local usb_device

  for usb_device in /sys/bus/usb/devices/*; do
    [[ -d "${usb_device}" ]] || continue
    if usb_device_matches_dock_path "${usb_device}"; then
      return 0
    fi
  done

  return 1
}

valid_rotation() {
  local value="$1"
  for rotation in "${SUPPORTED_ROTATIONS[@]}"; do
    [[ "$rotation" == "$value" ]] && return 0
  done
  return 1
}

normalize_percent() {
  local value="$1"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    log "Invalid backlight percentage: $value"
    exit 1
  fi
  if (( value > 100 )); then
    value=100
  fi
  printf '%s' "$value"
}

set_keyboard_backlight() {
  local target
  local led_path max brightness

  target="$(normalize_percent "$1")"

  led_path="$(find /sys/class/leds -maxdepth 1 -type l \( -iname '*kbd*' -o -iname '*keyboard*' -o -iname '*asus*' \) | head -n1 || true)"
  if [[ -z "$led_path" ]]; then
    log "No keyboard backlight device found."
    return 0
  fi

  if [[ ! -r "$led_path/max_brightness" ]]; then
    log "Unable to read max brightness from $led_path."
    return 0
  fi

  max="$(<"$led_path/max_brightness")"
  brightness=$(( max * target / 100 ))
  if (( target > 0 && brightness < 1 && max > 0 )); then
    brightness=1
  fi
  if (( brightness > max )); then
    brightness=$max
  fi

  if [[ -w "$led_path/brightness" ]]; then
    printf '%s' "$brightness" >"$led_path/brightness"
  else
    printf '%s' "$brightness" | sudo tee "$led_path/brightness" >/dev/null
  fi

  log "Keyboard backlight set to ${brightness}/${max} (${target}%)"
}

set_all_keyboard_backlights_off() {
  set_keyboard_backlight 0 || true

  if [[ -x "${FNKEYS_HELPER}" ]]; then
    "${FNKEYS_HELPER}" kbb 0 >/dev/null 2>&1 || \
      log "Fn-key helper could not switch detachable keyboard backlight off."
  fi
}

get_ac_online() {
  local ac
  local ac_online="0"

  for ac in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
    if [[ -f "$ac" ]]; then
      ac_online="$(<"$ac")"
      break
    fi
  done

  printf '%s' "$ac_online"
}

set_power_profile() {
  local ac_online
  ac_online="$(get_ac_online)"

  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    log "powerprofilesctl not available."
    return 0
  fi

  if [[ "$ac_online" == "1" ]]; then
    log "AC power detected → setting performance profile."
    sudo powerprofilesctl set performance || true
  else
    log "Battery power detected → setting balanced profile."
    sudo powerprofilesctl set balanced || sudo powerprofilesctl set power-saver || true
  fi
}

lid_close_action() {
  local ac_online
  ac_online="$(get_ac_online)"

  log "Lid closed → switching keyboard backlight off."
  set_all_keyboard_backlights_off

  if [[ "$ac_online" == "1" ]]; then
    log "Lid closed while charging/on AC → suspending."
    sudo systemctl suspend || log "Suspend command failed."
  else
    log "Lid closed while discharging/on battery → hibernating."
    sudo systemctl hibernate || log "Hibernate command failed."
  fi
}

find_lid_state_path() {
  local state_path

  if [[ "${LID_STATE_PATH}" != "auto" ]]; then
    [[ -r "${LID_STATE_PATH}" ]] && printf '%s' "${LID_STATE_PATH}"
    return
  fi

  for state_path in /proc/acpi/button/lid/*/state; do
    [[ -r "${state_path}" ]] || continue
    printf '%s' "${state_path}"
    return
  done
}

read_lid_state() {
  local state_path="${1}"
  local state=""

  state="$(<"${state_path}")"
  if [[ "${state}" == *closed* ]]; then
    printf 'closed'
  elif [[ "${state}" == *open* ]]; then
    printf 'open'
  else
    printf 'unknown'
  fi
}

watch_lid_state() {
  local state_path last_state current_state

  state_path="$(find_lid_state_path)"
  if [[ -z "${state_path}" ]]; then
    log "No readable lid state path found."
    return 1
  fi

  last_state="$(read_lid_state "${state_path}")"
  log "Watching lid state at ${state_path}; initial state: ${last_state}"

  while sleep "${LID_WATCH_INTERVAL_SECONDS}"; do
    current_state="$(read_lid_state "${state_path}")"
    if [[ "${current_state}" == "closed" && "${last_state}" != "closed" ]]; then
      lid_close_action
    fi
    last_state="${current_state}"
  done
}

run_system_service() {
  set_power_profile
  watch_lid_state
}

get_monitor_geometry() {
  local monitor="$1"
  local geometry

  if ! command -v xrandr >/dev/null 2>&1; then
    return 1
  fi

  geometry="$(xrandr --query | grep -E "^${monitor} connected" | sed -n 's/^.* connected[^0-9]*\([0-9]\+x[0-9]\++[0-9]\++[0-9]\+\).*$/\1/p')"
  [[ -n "$geometry" ]] || return 1
  printf '%s' "$geometry"
}

move_windows_to_main() {
  [[ "${MOVE_WINDOWS_TO_MAIN}" == true ]] || return 0

  if ! command -v wmctrl >/dev/null 2>&1 || ! command -v xrandr >/dev/null 2>&1; then
    log "wmctrl or xrandr not available; cannot move windows to $MAIN_SCREEN."
    return 0
  fi

  local geom
  geom="$(get_monitor_geometry "$MAIN_SCREEN")" || {
    log "Could not detect geometry for $MAIN_SCREEN."
    return 0
  }

  local main_w main_h main_x main_y dest_x dest_y
  IFS='x+' read -r main_w main_h main_x main_y <<<"$geom"
  dest_x=$((main_x + 20))
  dest_y=$((main_y + 20))

  while IFS= read -r id desktop x y w h rest; do
    [[ "$id" =~ ^0x[0-9a-fA-F]+$ ]] || continue
    log "Moving window $id to ${MAIN_SCREEN} at ${dest_x},${dest_y}."
    wmctrl -i -r "$id" -e "0,$dest_x,$dest_y,$w,$h" >/dev/null 2>&1 || \
      log "Failed to move window $id."
  done < <(wmctrl -lG)
}

refresh_plasma_shell() {
  [[ "${REFRESH_PLASMA_ON_LAYOUT}" == true ]] || return 0

  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell >/dev/null 2>&1 || true
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    log "Requested Plasma/KWin layout refresh."
  fi
}

run_kscreen_doctor() {
  if ! kscreen-doctor "$@" >/dev/null 2>&1; then
    log "kscreen-doctor failed to apply display layout."
    return 1
  fi
}

restart_plasma_shell() {
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
  log "Restarted Plasma Shell after attached layout."
}

move_plasma_panels() {
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
  log "Requested Plasma panel move to screen ${target_screen} for ${mode} mode."
}

apply_display_layout() {
  local mode="$1"
  local driver=""

  if command -v kscreen-doctor >/dev/null 2>&1; then
    driver="kscreen"
  elif command -v xrandr >/dev/null 2>&1; then
    driver="xrandr"
  else
    log "Neither kscreen-doctor nor xrandr is available."
    return 0
  fi

  if [[ "$mode" == "auto" ]]; then
    if keyboard_attached; then
      mode="attached"
    else
      mode="detached"
    fi
  fi

  log "Using display mode: $mode"

  if [[ "$driver" == "kscreen" ]]; then
    if [[ "$mode" == "attached" ]]; then
      log "Applying attached keyboard layout via kscreen-doctor."
      run_kscreen_doctor \
        output."$MAIN_SCREEN".enable \
        output."$MAIN_SCREEN".position.0,0 \
        output."$MAIN_SCREEN".rotation."$MAIN_ROTATION" \
        output."$LOWER_SCREEN".disable || return 0
      move_plasma_panels attached
      refresh_plasma_shell
      restart_plasma_shell
    else
      log "Applying detached keyboard layout via kscreen-doctor."
      run_kscreen_doctor \
        output."$MAIN_SCREEN".enable \
        output."$MAIN_SCREEN".position.0,0 \
        output."$MAIN_SCREEN".rotation."$MAIN_ROTATION" \
        output."$LOWER_SCREEN".enable \
        output."$LOWER_SCREEN".position."$LOWER_POSITION" \
        output."$LOWER_SCREEN".rotation."$LOWER_ROTATION" || return 0
      move_plasma_panels detached
      refresh_plasma_shell
    fi
  else
    if [[ "$mode" == "attached" ]]; then
      xrandr --output "$MAIN_SCREEN" --auto --rotate "$MAIN_ROTATION"
      xrandr --output "$LOWER_SCREEN" --auto --rotate "$LOWER_ROTATION"
      xrandr --output "$LOWER_SCREEN" --off
    else
      xrandr --output "$MAIN_SCREEN" --auto --rotate "$MAIN_ROTATION"
      xrandr --output "$LOWER_SCREEN" --auto --rotate "$LOWER_ROTATION"
    fi
  fi

  move_windows_to_main
}

show_status() {
  if keyboard_attached; then
    log "Keyboard state: attached"
  else
    log "Keyboard state: detached"
  fi
  log "Main screen: $MAIN_SCREEN rotation=$MAIN_ROTATION"
  log "Lower screen: $LOWER_SCREEN rotation=$LOWER_ROTATION"
  log "Backlight target: ${BACKLIGHT_LEVEL_PERCENT}%"
}

current_keyboard_mode() {
  if keyboard_attached; then
    printf 'attached'
  else
    printf 'detached'
  fi
}

apply_if_keyboard_mode_changed() {
  local current_mode

  current_mode="$(current_keyboard_mode)"
  if [[ "${current_mode}" != "${WATCH_KEYBOARD_MODE}" ]]; then
    log "Keyboard state changed: ${WATCH_KEYBOARD_MODE} -> ${current_mode}"
    WATCH_KEYBOARD_MODE="${current_mode}"
    if [[ "${MANAGE_DISPLAY_LAYOUT}" == true ]]; then
      apply_display_layout "${current_mode}"
    else
      log "Display layout management disabled."
    fi
  fi
}

watch_keyboard_state() {
  WATCH_KEYBOARD_MODE="$(current_keyboard_mode)"

  log "Watching keyboard state; initial mode: ${WATCH_KEYBOARD_MODE}"
  if [[ "${MANAGE_DISPLAY_LAYOUT}" == true ]]; then
    apply_display_layout "${WATCH_KEYBOARD_MODE}"
  else
    log "Display layout management disabled."
  fi

  if command -v udevadm >/dev/null 2>&1; then
    if watch_keyboard_state_udev; then
      return
    fi
    log "udevadm monitor unavailable; falling back to polling."
  fi

  log "Polling keyboard state every 2 seconds."
  while sleep 2; do
    apply_if_keyboard_mode_changed
  done
}

watch_keyboard_state_udev() {
  local line

  udevadm monitor --subsystem-match=usb --udev --property | while IFS= read -r line; do
    if [[ "${line}" == ACTION=* ]]; then
      sleep "${WATCH_DEBOUNCE_SECONDS}"
      apply_if_keyboard_mode_changed
    fi
  done
}

usage() {
  cat <<EOF
Usage: $0 <action> [options]

Actions:
  apply           Apply full configuration for current keyboard state
  watch           Watch USB attach/detach events and apply display layout
  display [auto|attached|detached]
                  Apply display layout for attached/detached keyboard mode
  rotate <main|lower|both> <rotation>
                  Apply rotation values for this run
  light           Set keyboard backlight level to configured percent
  light-off       Switch all known keyboard backlights off
  power           Apply power profile based on AC/battery state
  lid             Suspend on AC or hibernate on battery when lid closes
  lid-watch       Watch lid state and run lid policy on close
  service         Apply system policy and watch lid state
  status          Show current keyboard and screen state
  version         Show helper version
  help            Show this help text

Supported rotations: ${SUPPORTED_ROTATIONS[*]}
EOF
}

main() {
  load_config

  case "${1:-apply}" in
    apply)
      set_keyboard_backlight "$BACKLIGHT_LEVEL_PERCENT"
      set_power_profile
      if [[ "${MANAGE_DISPLAY_LAYOUT}" == true ]]; then
        apply_display_layout auto
      else
        log "Display layout management disabled."
      fi
      ;;
    display)
      apply_display_layout "${2:-auto}"
      ;;
    rotate)
      local target="${2:-both}"
      local rotation="${3:-}"
      if [[ -z "$rotation" ]]; then
        log "Rotation value missing."
        usage
        exit 1
      fi
      if ! valid_rotation "$rotation"; then
        log "Invalid rotation: $rotation"
        usage
        exit 1
      fi
      if [[ "$target" == "main" || "$target" == "both" ]]; then
        MAIN_ROTATION="$rotation"
      fi
      if [[ "$target" == "lower" || "$target" == "both" ]]; then
        LOWER_ROTATION="$rotation"
      fi
      log "Rotation updated: main=$MAIN_ROTATION lower=$LOWER_ROTATION"
      apply_display_layout auto
      ;;
    light)
      set_keyboard_backlight "$BACKLIGHT_LEVEL_PERCENT"
      ;;
    light-off)
      set_all_keyboard_backlights_off
      ;;
    power)
      set_power_profile
      ;;
    watch)
      watch_keyboard_state
      ;;
    lid)
      lid_close_action
      ;;
    lid-watch)
      watch_lid_state
      ;;
    service)
      run_system_service
      ;;
    status)
      show_status
      ;;
    version|--version|-V)
      log "Version: ${HELPER_VERSION}"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      log "Unknown action: ${1:-}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
