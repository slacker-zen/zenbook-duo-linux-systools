#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PKG_NAME="zenbook-duo-systools"
PKG_VERSION="${PKG_VERSION:-1.3}"
PKG_RELEASE="${PKG_RELEASE:-10}"
ARCH="${DEB_ARCH:-amd64}"
BUILD_DIR="${REPO_DIR}/build/deb"
PKG_DIR="${BUILD_DIR}/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${ARCH}"
OUT_DIR="${REPO_DIR}/dist"

# shellcheck source=../../scripts/pkg-env.sh
source "${REPO_DIR}/scripts/pkg-env.sh"

usage() {
  cat <<EOF
Usage: $0 [--install-prereqs] [--no-ui-build]

Builds a Debian package for Zorin/Ubuntu-family distributions.
EOF
}

INSTALL_PREREQS=false
BUILD_UI=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-prereqs)
      INSTALL_PREREQS=true
      ;;
    --no-ui-build)
      BUILD_UI=false
      ;;
    help|--help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$(zbd_package_family)" != "debian" ]]; then
  echo "This builder is intended for Zorin/Ubuntu/Debian-family systems." >&2
  echo "Use makepkg on Arch/CachyOS." >&2
  exit 1
fi

if [[ "${INSTALL_PREREQS}" == true ]]; then
  zbd_install_prerequisites build
  zbd_install_prerequisites sysstates
  zbd_install_prerequisites fnkeys
fi

if [[ "${BUILD_UI}" == true ]]; then
  (
    cd "${REPO_DIR}/ui"
    npm install --no-package-lock
    npm run tauri -- build --no-bundle -- --locked
  )
fi

if [[ ! -x "${REPO_DIR}/ui/src-tauri/target/release/zenbook-duo-ui" ]]; then
  echo "Missing UI binary: ui/src-tauri/target/release/zenbook-duo-ui" >&2
  echo "Run without --no-ui-build, or build the Tauri UI first." >&2
  exit 1
fi

rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/DEBIAN" "${OUT_DIR}"

install -Dm755 "${REPO_DIR}/coordinator/zenbook-duo-matrix.sh" "${PKG_DIR}/usr/bin/zenbook-duo-matrix"
install -Dm755 "${REPO_DIR}/control/zenbook-duo-control.sh" "${PKG_DIR}/usr/bin/zenbook-duo-control"
install -Dm755 "${REPO_DIR}/sysstates/duo-sysstates.sh" "${PKG_DIR}/usr/bin/zenbook-duo-systools"
install -Dm755 "${REPO_DIR}/fnkeys/duo-fnkeys.sh" "${PKG_DIR}/usr/bin/zenbook-duo-systools-fnkeys"
install -Dm755 "${REPO_DIR}/ui/src-tauri/target/release/zenbook-duo-ui" "${PKG_DIR}/usr/bin/zenbook-duo-ui"

install -Dm644 "${REPO_DIR}/sysstates/duo-sysstates.conf" "${PKG_DIR}/etc/zenbook-duo/duo-sysstates.conf"
install -Dm644 "${REPO_DIR}/fnkeys/fnkeys.conf" "${PKG_DIR}/etc/zenbook-duo/fnkeys.conf"

install -Dm440 "${REPO_DIR}/sysstates/sudoers-zenbook-duo-systools" "${PKG_DIR}/etc/sudoers.d/zenbook-duo-systools"
install -Dm440 "${REPO_DIR}/fnkeys/sudoers-zenbook-duo-systools-fnkeys" "${PKG_DIR}/etc/sudoers.d/zenbook-duo-systools-fnkeys"

install -Dm644 "${REPO_DIR}/sysstates/zenbook-duo-systools.service" "${PKG_DIR}/lib/systemd/system/zenbook-duo-systools.service"
install -Dm644 "${REPO_DIR}/coordinator/zenbook-duo-matrix.service" "${PKG_DIR}/usr/lib/systemd/user/zenbook-duo-matrix.service"
install -Dm755 "${REPO_DIR}/sysstates/zenbook-duo-systools.sleep" "${PKG_DIR}/lib/systemd/system-sleep/zenbook-duo-systools"

install -Dm644 "${REPO_DIR}/ui/zenbook-duo-ui.desktop" "${PKG_DIR}/usr/share/applications/zenbook-duo-ui.desktop"
install -Dm644 "${REPO_DIR}/ui/zenbook-duo-ui-autostart.desktop" "${PKG_DIR}/etc/xdg/autostart/zenbook-duo-ui.desktop"
install -Dm644 "${REPO_DIR}/ui/src-tauri/icons/128x128.png" "${PKG_DIR}/usr/share/icons/hicolor/128x128/apps/zenbook-duo-ui.png"

install -Dm755 "${REPO_DIR}/fnkeys/backlight.py" "${PKG_DIR}/usr/lib/zenbook-duo-fnkeys/backlight.py"
install -Dm755 "${REPO_DIR}/fnkeys/input_watcher.py" "${PKG_DIR}/usr/lib/zenbook-duo-fnkeys/input_watcher.py"
install -Dm644 "${REPO_DIR}/fnkeys/72-zenbook-duo-fnkeys-input.rules" "${PKG_DIR}/usr/lib/udev/rules.d/72-zenbook-duo-fnkeys-input.rules"

install -Dm644 "${REPO_DIR}/README.md" "${PKG_DIR}/usr/share/doc/zenbook-duo-systools/README.md"
install -Dm644 "${REPO_DIR}/LICENSE" "${PKG_DIR}/usr/share/doc/zenbook-duo-systools/copyright"

sed \
  -e "s/@VERSION@/${PKG_VERSION}-${PKG_RELEASE}/g" \
  -e "s/@ARCH@/${ARCH}/g" \
  "${SCRIPT_DIR}/control.in" >"${PKG_DIR}/DEBIAN/control"
install -Dm755 "${SCRIPT_DIR}/postinst" "${PKG_DIR}/DEBIAN/postinst"
install -Dm755 "${SCRIPT_DIR}/prerm" "${PKG_DIR}/DEBIAN/prerm"
install -Dm755 "${SCRIPT_DIR}/postrm" "${PKG_DIR}/DEBIAN/postrm"

dpkg-deb --build --root-owner-group "${PKG_DIR}" "${OUT_DIR}/${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${ARCH}.deb"
