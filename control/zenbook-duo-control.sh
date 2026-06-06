#!/usr/bin/env bash
set -euo pipefail

SYS_CONFIG_FILE="${ZENBOOK_DUO_SYS_CONFIG:-/etc/zenbook-duo/duo-sysstates.conf}"
FN_CONFIG_FILE="${ZENBOOK_DUO_FN_CONFIG:-/etc/zenbook-duo/fnkeys.conf}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

MATRIX_HELPER="${ZENBOOK_DUO_MATRIX:-/usr/bin/zenbook-duo-matrix}"
SYSSTATES_HELPER="${ZENBOOK_DUO_SYSTOOLS:-/usr/bin/zenbook-duo-systools}"
FNKEYS_HELPER="${ZENBOOK_DUO_FNKEYS:-/usr/bin/zenbook-duo-systools-fnkeys}"
LOG_DIR="${ZENBOOK_DUO_LOG_DIR:-${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/zenbook-duo}"
LOG_FILE="${LOG_DIR}/control.log"

MAIN_SCREEN="eDP-1"
LOWER_SCREEN="eDP-2"
MAIN_BACKLIGHT_PATH="/sys/class/backlight/intel_backlight/brightness"
LOWER_BACKLIGHT_PATH="/sys/class/backlight/card1-eDP-2-backlight/brightness"
FNKEYS_BACKLIGHT_STATE_FILE="/tmp/duo/kb-backlight-level"

if [[ ! -e "${MATRIX_HELPER}" && -x "${REPO_ROOT}/coordinator/zenbook-duo-matrix.sh" ]]; then
  MATRIX_HELPER="${REPO_ROOT}/coordinator/zenbook-duo-matrix.sh"
fi
if [[ ! -e "${SYSSTATES_HELPER}" && -x "${REPO_ROOT}/sysstates/duo-sysstates.sh" ]]; then
  SYSSTATES_HELPER="${REPO_ROOT}/sysstates/duo-sysstates.sh"
fi
if [[ ! -e "${FNKEYS_HELPER}" && -x "${REPO_ROOT}/fnkeys/duo-fnkeys.sh" ]]; then
  FNKEYS_HELPER="${REPO_ROOT}/fnkeys/duo-fnkeys.sh"
fi
if [[ ! -f "${SYS_CONFIG_FILE}" && -f "${REPO_ROOT}/sysstates/duo-sysstates.conf" ]]; then
  SYS_CONFIG_FILE="${REPO_ROOT}/sysstates/duo-sysstates.conf"
fi
if [[ ! -f "${FN_CONFIG_FILE}" && -f "${REPO_ROOT}/fnkeys/fnkeys.conf" ]]; then
  FN_CONFIG_FILE="${REPO_ROOT}/fnkeys/fnkeys.conf"
fi

mkdir -p "${LOG_DIR}" 2>/dev/null || true

log() {
  local message="$*"
  local stamp=""
  stamp="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date +%s)"
  printf '[%s] [zenbook-duo-control] %s\n' "${stamp}" "${message}" >>"${LOG_FILE}" 2>/dev/null || true
}

load_display_config() {
  if [[ -f "${FN_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${FN_CONFIG_FILE}"
  fi

  MAIN_SCREEN="${DUO_MAIN_SCREEN:-${MAIN_SCREEN}}"
  LOWER_SCREEN="${DUO_LOWER_SCREEN:-${LOWER_SCREEN}}"
  MAIN_BACKLIGHT_PATH="${FNKEYS_MAIN_BACKLIGHT_PATH:-${MAIN_BACKLIGHT_PATH}}"
  LOWER_BACKLIGHT_PATH="${FNKEYS_LOWER_BACKLIGHT_PATH:-${LOWER_BACKLIGHT_PATH}}"
}

load_backlight_config() {
  if [[ -f "${SYS_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${SYS_CONFIG_FILE}"
  fi
  if [[ -f "${FN_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${FN_CONFIG_FILE}"
  fi
}

read_builtin_keyboard_backlight_percent() {
  local led_path="" max="" value=""
  led_path="$(find /sys/class/leds -maxdepth 2 -type f \( -iname '*kbd*' -o -iname '*keyboard*' -o -iname '*asus*' \) -name brightness | head -n1 || true)"
  [[ -n "${led_path}" && -r "${led_path}" && -r "${led_path%/*}/max_brightness" ]] || return 0

  max="$(cat "${led_path%/*}/max_brightness" 2>/dev/null || true)"
  value="$(cat "${led_path}" 2>/dev/null || true)"
  if [[ "${max}" =~ ^[0-9]+$ && "${value}" =~ ^[0-9]+$ && "${max}" -gt 0 ]]; then
    printf '%s' "$(( value * 100 / max ))"
  fi
}

read_detachable_keyboard_backlight_level() {
  local value=""
  value="$(cat "${FNKEYS_BACKLIGHT_STATE_FILE}" 2>/dev/null || true)"
  if [[ "${value}" =~ ^[0-3]$ ]]; then
    printf '%s' "${value}"
  elif [[ "${FNKEYS_BACKLIGHT_LEVEL:-}" =~ ^[0-3]$ ]]; then
    printf '%s' "${FNKEYS_BACKLIGHT_LEVEL}"
  fi
}

run_helper() {
  local helper="$1"
  shift
  local status=0 started=0 elapsed=0

  started="$(date +%s)"
  log "helper start helper=${helper} args=$*"
  case "${helper}" in
    matrix)
      "${MATRIX_HELPER}" "$@" || status=$?
      ;;
    sysstates)
      "${SYSSTATES_HELPER}" "$@" || status=$?
      ;;
    fnkeys)
      "${FNKEYS_HELPER}" "$@" || status=$?
      ;;
    *)
      printf 'Unknown helper: %s\n' "${helper}" >&2
      log "helper unknown helper=${helper}"
      return 2
      ;;
  esac
  elapsed=$(( $(date +%s) - started ))
  log "helper done helper=${helper} status=${status} elapsed=${elapsed}s args=$*"
  return "${status}"
}

status_json() {
  load_backlight_config

  local matrix_output="" sysstates_output="" builtin_backlight="" detachable_backlight=""
  matrix_output="$(run_helper matrix status 2>&1 || true)"
  sysstates_output="$(run_helper sysstates status 2>&1 || true)"
  builtin_backlight="$(read_builtin_keyboard_backlight_percent)"
  detachable_backlight="$(read_detachable_keyboard_backlight_level)"

  MATRIX_OUTPUT="${matrix_output}" \
  SYSSTATES_OUTPUT="${sysstates_output}" \
  BUILTIN_KEYBOARD_BACKLIGHT="${builtin_backlight}" \
  DETACHABLE_KEYBOARD_BACKLIGHT="${detachable_backlight}" \
  python3 - <<'PY'
import json
import os

matrix = {}
for line in os.environ.get("MATRIX_OUTPUT", "").splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        matrix[key.strip()] = value.strip().strip('"').strip("'")

print(json.dumps({
    "matrix": matrix,
    "sysstates": os.environ.get("SYSSTATES_OUTPUT", ""),
    "keyboard_backlight": {
        "built_in_percent": int(os.environ["BUILTIN_KEYBOARD_BACKLIGHT"]) if os.environ.get("BUILTIN_KEYBOARD_BACKLIGHT", "").isdigit() else None,
        "detachable_level": int(os.environ["DETACHABLE_KEYBOARD_BACKLIGHT"]) if os.environ.get("DETACHABLE_KEYBOARD_BACKLIGHT", "").isdigit() else None,
        "detachable_max": 3,
    },
}, separators=(",", ":")))
PY
}

config_list_json() {
  SYS_CONFIG_FILE="${SYS_CONFIG_FILE}" FN_CONFIG_FILE="${FN_CONFIG_FILE}" python3 - <<'PY'
import json
import os

targets = [
    ("sysstates", "Sysstates", os.environ["SYS_CONFIG_FILE"]),
    ("fnkeys", "Fnkeys", os.environ["FN_CONFIG_FILE"]),
]

def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value

def kind(value):
    if value in ("true", "false"):
        return "boolean"
    try:
        float(value)
        return "number"
    except ValueError:
        return "text"

def parse(path):
    entries = []
    descriptions = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("#"):
                text = stripped[1:].strip()
                if text:
                    descriptions.append(text)
                continue
            if stripped and "=" in stripped and not stripped.startswith("#"):
                key, value = stripped.split("=", 1)
                key = key.strip()
                if all(character == "_" or character.isalnum() for character in key):
                    value = unquote(value)
                    entries.append({
                        "key": key,
                        "value": value,
                        "kind": kind(value),
                        "description": descriptions[-1] if descriptions else "Helper setting",
                    })
            if stripped:
                descriptions = []
    return entries

files = []
for file_id, title, path in targets:
    files.append({
        "id": file_id,
        "title": title,
        "path": path,
        "writable": os.access(path, os.W_OK),
        "entries": parse(path),
    })

print(json.dumps(files, separators=(",", ":")))
PY
}

config_write() {
  local file_id="${1:-}"
  local entries_file="${2:-}"
  local target=""

  case "${file_id}" in
    sysstates)
      target="${SYS_CONFIG_FILE}"
      ;;
    fnkeys)
      target="${FN_CONFIG_FILE}"
      ;;
    *)
      printf 'Unknown config file: %s\n' "${file_id}" >&2
      return 2
      ;;
  esac

  [[ -f "${entries_file}" ]] || {
    printf 'Entries JSON file does not exist: %s\n' "${entries_file}" >&2
    return 2
  }

  TARGET_CONFIG="${target}" ENTRIES_FILE="${entries_file}" python3 - <<'PY'
import json
import os
import subprocess
import tempfile

target = os.environ["TARGET_CONFIG"]
entries_file = os.environ["ENTRIES_FILE"]

with open(entries_file, encoding="utf-8") as handle:
    updates = {entry["key"]: entry["value"] for entry in json.load(handle)}

def parse_assignment(line):
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        return None
    key, _ = stripped.split("=", 1)
    key = key.strip()
    if all(character == "_" or character.isalnum() for character in key):
        return key
    return None

def format_value(value):
    if value in ("true", "false"):
        return value
    try:
        float(value)
        return value
    except ValueError:
        pass
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

with open(target, encoding="utf-8") as handle:
    source_lines = handle.read().splitlines()

seen = set()
lines = []
for line in source_lines:
    key = parse_assignment(line)
    if key and key in updates:
        lines.append(f"{key}={format_value(updates[key])}")
        seen.add(key)
    else:
        lines.append(line)

for key, value in updates.items():
    if key not in seen:
        lines.append(f"{key}={format_value(value)}")

content = "\n".join(lines) + "\n"

try:
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(content)
except PermissionError:
    fd, temp_path = tempfile.mkstemp(prefix="zenbook-duo-config-", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        subprocess.run(["pkexec", "install", "-m", "0644", temp_path, target], check=True)
    finally:
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass
PY
}

normalize_percent() {
  local value="${1}"
  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    printf 'Invalid percent: %s\n' "${value}" >&2
    return 1
  fi
  if (( value < 0 )); then
    value=0
  elif (( value > 100 )); then
    value=100
  fi
  printf '%s' "${value}"
}

read_brightness_percent() {
  local path="${1}"
  local max="" current=""

  [[ -r "${path}" ]] || return 1
  max="$(cat "${path%/*}/max_brightness" 2>/dev/null || true)"
  current="$(cat "${path}" 2>/dev/null || true)"
  if [[ ! "${max}" =~ ^[0-9]+$ || "${max}" -le 0 || ! "${current}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  printf '%s' "$(( (current * 100 + max / 2) / max ))"
}

write_brightness_percent() {
  local path="${1}"
  local percent="${2}"
  local max="" brightness=""

  percent="$(normalize_percent "${percent}")"
  [[ -e "${path}" ]] || return 1
  max="$(cat "${path%/*}/max_brightness" 2>/dev/null || true)"
  if [[ ! "${max}" =~ ^[0-9]+$ || "${max}" -le 0 ]]; then
    return 1
  fi

  brightness=$(( max * percent / 100 ))
  if (( percent > 0 && brightness < 1 )); then
    brightness=1
  elif (( brightness > max )); then
    brightness="${max}"
  fi

  if [[ -w "${path}" ]]; then
    printf '%s' "${brightness}" >"${path}"
  else
    printf '%s' "${brightness}" | sudo /usr/bin/tee "${path}" >/dev/null
  fi
}

display_path_for_target() {
  case "${1:-}" in
    main|edp-1|eDP-1|"${MAIN_SCREEN}")
      printf '%s' "${MAIN_BACKLIGHT_PATH}"
      ;;
    lower|edp-2|eDP-2|"${LOWER_SCREEN}")
      printf '%s' "${LOWER_BACKLIGHT_PATH}"
      ;;
    *)
      printf 'Unknown display target: %s\n' "${1:-}" >&2
      return 2
      ;;
  esac
}

display_brightness_json() {
  load_display_config
  local main_value="" lower_value=""
  main_value="$(read_brightness_percent "${MAIN_BACKLIGHT_PATH}" 2>/dev/null || true)"
  lower_value="$(read_brightness_percent "${LOWER_BACKLIGHT_PATH}" 2>/dev/null || true)"

  MAIN_SCREEN="${MAIN_SCREEN}" LOWER_SCREEN="${LOWER_SCREEN}" \
  MAIN_PATH="${MAIN_BACKLIGHT_PATH}" LOWER_PATH="${LOWER_BACKLIGHT_PATH}" \
  MAIN_VALUE="${main_value}" LOWER_VALUE="${lower_value}" python3 - <<'PY'
import json
import os

def screen(key, name_key, path_key, value_key):
    raw = os.environ.get(value_key, "")
    return {
        "id": key,
        "name": os.environ[name_key],
        "path": os.environ[path_key],
        "available": bool(raw),
        "percent": int(raw) if raw.isdigit() else None,
    }

print(json.dumps({
    "main": screen("main", "MAIN_SCREEN", "MAIN_PATH", "MAIN_VALUE"),
    "lower": screen("lower", "LOWER_SCREEN", "LOWER_PATH", "LOWER_VALUE"),
}, separators=(",", ":")))
PY
}

display_brightness_set() {
  load_display_config
  local target="${1:-}"
  local percent="${2:-}"
  local path=""

  path="$(display_path_for_target "${target}")"
  percent="$(normalize_percent "${percent}")"
  write_brightness_percent "${path}" "${percent}"
  display_brightness_json
}

display_brightness_step() {
  load_display_config
  local target="${1:-}"
  local step="${2:-}"
  local path="" current="" next=""

  path="$(display_path_for_target "${target}")"
  step="$(normalize_percent "${step}")"
  if (( step < 1 )); then
    step=1
  fi
  current="$(read_brightness_percent "${path}" 2>/dev/null || true)"
  if [[ ! "${current}" =~ ^[0-9]+$ ]]; then
    current=0
  fi

  next=$(( current + step ))
  if (( next > 100 )); then
    next="${step}"
  fi

  write_brightness_percent "${path}" "${next}"
  display_brightness_json
}

usage() {
  cat <<EOF
Usage: $0 <command> [args]

Commands:
  status --json
  config list --json
  config write <sysstates|fnkeys> <entries-json-file>
  display brightness --json
  display brightness set <main|lower> <percent>
  display brightness step <main|lower> <increment-percent>
  action <matrix|sysstates|fnkeys> [helper-args...]
EOF
}

main() {
  case "${1:-}" in
    status)
      [[ "${2:-}" == "--json" ]] || { usage; return 2; }
      status_json
      ;;
    config)
      case "${2:-}" in
        list)
          [[ "${3:-}" == "--json" ]] || { usage; return 2; }
          config_list_json
          ;;
        write)
          config_write "${3:-}" "${4:-}"
          ;;
        *)
          usage
          return 2
          ;;
      esac
      ;;
    display)
      case "${2:-}" in
        brightness)
          case "${3:-}" in
            --json)
              display_brightness_json
              ;;
            set)
              display_brightness_set "${4:-}" "${5:-}"
              ;;
            step)
              display_brightness_step "${4:-}" "${5:-}"
              ;;
            *)
              usage
              return 2
              ;;
          esac
          ;;
        *)
          usage
          return 2
          ;;
      esac
      ;;
    action)
      shift
      run_helper "$@"
      ;;
    help|--help|-h|"")
      usage
      ;;
    *)
      usage
      return 2
      ;;
  esac
}

main "$@"
