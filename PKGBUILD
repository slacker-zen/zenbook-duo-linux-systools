# Maintainer: nekropolit <m.zenker@userart.net>

pkgname=zenbook-duo-systools
pkgver=1.3
pkgrel=10
pkgdesc='ASUS Zenbook Duo event matrix, Fn-key, display, power, lid, and tray helpers'
arch=(x86_64)
url='https://github.com/nekropolit/zenbook-duo-linux-systools'
license=(MIT)
depends=(
  bash
  bluez-utils
  glib2
  gtk3
  inotify-tools
  kscreen
  libayatana-appindicator
  libinput
  libnotify
  networkmanager
  power-profiles-daemon
  python-evdev
  python-pyusb
  qt6-tools
  sudo
  systemd
  usbutils
  webkit2gtk-4.1
)
makedepends=(
  npm
  rust
)
backup=(
  etc/zenbook-duo/duo-sysstates.conf
  etc/zenbook-duo/fnkeys.conf
  etc/sudoers.d/zenbook-duo-systools
  etc/sudoers.d/zenbook-duo-systools-fnkeys
)
install=zenbook-duo-systools.install
conflicts=(
  zenbook-duo-systools-fnkeys
  zenbook-duo-linux-systools-sysstates
  zenbook-duo-linux-systools-fnkeys
)
replaces=(
  zenbook-duo-systools-fnkeys
  zenbook-duo-linux-systools-sysstates
  zenbook-duo-linux-systools-fnkeys
)
provides=(
  "zenbook-duo-linux-systools-sysstates=${pkgver}"
  "zenbook-duo-linux-systools-fnkeys=${pkgver}"
  "zenbook-duo-systools-fnkeys=${pkgver}"
)
source=()
sha256sums=()

build() {
  cd "${startdir}/ui"
  npm install --no-package-lock
  npm run tauri -- build --no-bundle -- --locked
}

package() {
  install -Dm755 "${startdir}/coordinator/zenbook-duo-matrix.sh" "${pkgdir}/usr/bin/zenbook-duo-matrix"
  install -Dm755 "${startdir}/control/zenbook-duo-control.sh" "${pkgdir}/usr/bin/zenbook-duo-control"
  install -Dm755 "${startdir}/sysstates/duo-sysstates.sh" "${pkgdir}/usr/bin/zenbook-duo-systools"
  install -Dm755 "${startdir}/fnkeys/duo-fnkeys.sh" "${pkgdir}/usr/bin/zenbook-duo-systools-fnkeys"
  install -Dm755 "${startdir}/ui/src-tauri/target/release/zenbook-duo-ui" "${pkgdir}/usr/bin/zenbook-duo-ui"

  install -Dm644 "${startdir}/sysstates/duo-sysstates.conf" "${pkgdir}/etc/zenbook-duo/duo-sysstates.conf"
  install -Dm644 "${startdir}/fnkeys/fnkeys.conf" "${pkgdir}/etc/zenbook-duo/fnkeys.conf"

  install -Dm440 "${startdir}/sysstates/sudoers-zenbook-duo-systools" "${pkgdir}/etc/sudoers.d/zenbook-duo-systools"
  install -Dm440 "${startdir}/fnkeys/sudoers-zenbook-duo-systools-fnkeys" "${pkgdir}/etc/sudoers.d/zenbook-duo-systools-fnkeys"

  install -Dm644 "${startdir}/sysstates/zenbook-duo-systools.service" "${pkgdir}/usr/lib/systemd/system/zenbook-duo-systools.service"
  install -Dm644 "${startdir}/coordinator/zenbook-duo-matrix.service" "${pkgdir}/usr/lib/systemd/user/zenbook-duo-matrix.service"
  install -Dm755 "${startdir}/sysstates/zenbook-duo-systools.sleep" "${pkgdir}/usr/lib/systemd/system-sleep/zenbook-duo-systools"

  install -Dm644 "${startdir}/ui/zenbook-duo-ui.desktop" "${pkgdir}/usr/share/applications/zenbook-duo-ui.desktop"
  install -Dm644 "${startdir}/ui/zenbook-duo-ui-autostart.desktop" "${pkgdir}/etc/xdg/autostart/zenbook-duo-ui.desktop"
  install -Dm644 "${startdir}/ui/src-tauri/icons/128x128.png" "${pkgdir}/usr/share/icons/hicolor/128x128/apps/zenbook-duo-ui.png"

  install -Dm755 "${startdir}/fnkeys/backlight.py" "${pkgdir}/usr/lib/zenbook-duo-fnkeys/backlight.py"
  install -Dm755 "${startdir}/fnkeys/input_watcher.py" "${pkgdir}/usr/lib/zenbook-duo-fnkeys/input_watcher.py"
  install -Dm644 "${startdir}/fnkeys/72-zenbook-duo-fnkeys-input.rules" "${pkgdir}/usr/lib/udev/rules.d/72-zenbook-duo-fnkeys-input.rules"

  install -Dm644 "${startdir}/README.md" "${pkgdir}/usr/share/doc/zenbook-duo-systools/README.md"
  install -Dm644 "${startdir}/LICENSE" "${pkgdir}/usr/share/licenses/zenbook-duo-systools/LICENSE"
}
