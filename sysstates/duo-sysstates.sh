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
HELPER_VERSION="0.9"

# Default values, override in config file
LOWER_SCREEN="eDP-2"
MAIN_SCREEN="eDP-1"
MAIN_ROTATION="normal"
LOWER_ROTATION="normal"
KEYBOARD_MATCH="Keyboard|ASUS|ASUSTeK|AT Translated Set 2 keyboard"
KEYBOARD_BT_MAC="E9:C7:F1:96:05:3C"
KEYBOARD_BT_NAME="ASUS Zenbook Duo Keyboard"
BACKLIGHT_LEVEL_PERCENT=50
MOVE_WINDOWS_TO_MAIN=false

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

keyboard_attached() {
  if command -v libinput >/dev/null 2>&1; then
    if libinput list-devices 2>/dev/null | grep -Eiq "${KEYBOARD_MATCH}"; then
      return 0
    fi
  fi

  if command -v bluetoothctl >/dev/null 2>&1; then
    if [[ -n "${KEYBOARD_BT_MAC}" ]] && bluetoothctl info "${KEYBOARD_BT_MAC}" 2>/dev/null | grep -q "Connected: yes"; then
      return 0
    fi

    if [[ -n "${KEYBOARD_BT_NAME}" ]]; then
      local mac
      mac=$(bluetoothctl devices 2>/dev/null | awk -v name="${KEYBOARD_BT_NAME}" '
        BEGIN { IGNORECASE=1 }
        index($0, name) { print $2; exit }
      ' || true)
      if [[ -n "${mac}" ]] && bluetoothctl info "${mac}" 2>/dev/null | grep -q "Connected: yes"; then
        return 0
      fi
    fi
  fi

  for candidate in /dev/input/by-id/*kbd* /dev/input/by-id/*Keyboard* /dev/input/by-path/*kbd* /dev/input/by-path/*keyboard*; do
    [[ -e "$candidate" ]] && return 0
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

  if [[ "$ac_online" == "1" ]]; then
    log "Lid closed while on AC → suspending."
    sudo systemctl suspend || log "Suspend command failed."
  else
    log "Lid closed on battery → hibernating."
    sudo systemctl hibernate || log "Hibernate command failed."
  fi
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
      kscreen-doctor \
        output."$MAIN_SCREEN".enable \
        output."$MAIN_SCREEN".rotation."$MAIN_ROTATION" \
        output."$LOWER_SCREEN".disable
    else
      log "Applying detached keyboard layout via kscreen-doctor."
      kscreen-doctor \
        output."$MAIN_SCREEN".enable \
        output."$MAIN_SCREEN".rotation."$MAIN_ROTATION" \
        output."$LOWER_SCREEN".enable \
        output."$LOWER_SCREEN".rotation."$LOWER_ROTATION"
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

usage() {
  cat <<EOF
Usage: $0 <action> [options]

Actions:
  apply           Apply full configuration for current keyboard state
  display [auto|attached|detached]
                  Apply display layout for attached/detached keyboard mode
  rotate <main|lower|both> <rotation>
                  Apply rotation values for this run
  light           Set keyboard backlight level to configured percent
  power           Apply power profile based on AC/battery state
  lid             Suspend on AC or hibernate on battery when lid closes
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
      apply_display_layout auto
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
    power)
      set_power_profile
      ;;
    lid)
      lid_close_action
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
