#!/usr/bin/env bash

zbd_os_id() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    printf '%s\n' "${ID:-unknown}"
    return
  fi
  printf 'unknown\n'
}

zbd_os_like() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    printf '%s\n' "${ID_LIKE:-}"
    return
  fi
  printf '\n'
}

zbd_package_family() {
  local id like
  id="$(zbd_os_id)"
  like="$(zbd_os_like)"

  case " ${id} ${like} " in
    *" arch "*|*" cachyos "*)
      printf 'arch\n'
      ;;
    *" zorin "*|*" ubuntu "*|*" debian "*)
      printf 'debian\n'
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

zbd_prerequisites() {
  local group="${1}"
  local family="${2:-$(zbd_package_family)}"

  case "${family}:${group}" in
    arch:sysstates)
      printf '%s\n' bluez-utils kscreen power-profiles-daemon qt6-tools sudo
      ;;
    arch:fnkeys)
      printf '%s\n' bluez-utils glib2 inotify-tools kscreen libinput libnotify networkmanager python-evdev python-pyusb qt6-tools sudo usbutils
      ;;
    arch:build)
      printf '%s\n' npm rust
      ;;
    debian:sysstates)
      printf '%s\n' bluez kscreen power-profiles-daemon qt6-tools-dev-tools sudo
      ;;
    debian:fnkeys)
      printf '%s\n' bluez inotify-tools kscreen libglib2.0-bin libinput-tools libnotify-bin network-manager python3-evdev python3-usb qt6-tools-dev-tools sudo usbutils
      ;;
    debian:build)
      printf '%s\n' build-essential cargo curl dpkg-dev libayatana-appindicator3-dev libgtk-3-dev libwebkit2gtk-4.1-dev npm rustc
      ;;
    *)
      return 1
      ;;
  esac
}

zbd_install_prerequisites() {
  local group="${1}"
  local family
  family="$(zbd_package_family)"

  case "${family}" in
    arch)
      mapfile -t packages < <(zbd_prerequisites "${group}" "${family}")
      sudo pacman -Sy --needed --noconfirm "${packages[@]}"
      ;;
    debian)
      mapfile -t packages < <(zbd_prerequisites "${group}" "${family}")
      sudo apt-get update
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
      ;;
    *)
      echo "Unsupported distribution for automatic prerequisites: $(zbd_os_id)" >&2
      echo "Install the '${group}' prerequisites manually, then rerun this setup." >&2
      return 1
      ;;
  esac
}
