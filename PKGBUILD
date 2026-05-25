# Maintainer: nekropolit <m.zenker@userart.net>

pkgbase=zenbook-duo-linux-systools
pkgname=(zenbook-duo-systools zenbook-duo-systools-fnkeys)
pkgver=1.0
pkgrel=5
pkgdesc='ASUS Zenbook Duo helpers for Arch-based KDE Plasma Wayland systems'
arch=(any)
url='https://github.com/nekropolit/zenbook-duo-linux-systools'
license=(MIT)
source=()
sha256sums=()

package_zenbook-duo-systools() {
  pkgdesc='ASUS Zenbook Duo system-state helper'
  depends=(bash kscreen power-profiles-daemon qt6-tools sudo systemd)
  backup=(
    etc/zenbook-duo/duo-sysstates.conf
    etc/sudoers.d/zenbook-duo-systools
  )
  install=sysstates/zenbook-duo-systools.install
  conflicts=(zenbook-duo-linux-systools-sysstates)
  replaces=(zenbook-duo-linux-systools-sysstates)
  provides=("zenbook-duo-linux-systools-sysstates=${pkgver}")

  install -Dm755 "${startdir}/sysstates/duo-sysstates.sh" "${pkgdir}/usr/bin/zenbook-duo-systools"
  install -Dm644 "${startdir}/sysstates/duo-sysstates.conf" "${pkgdir}/etc/zenbook-duo/duo-sysstates.conf"
  install -Dm440 "${startdir}/sysstates/sudoers-zenbook-duo-systools" "${pkgdir}/etc/sudoers.d/zenbook-duo-systools"
  install -Dm644 "${startdir}/sysstates/zenbook-duo-systools.service" "${pkgdir}/usr/lib/systemd/system/zenbook-duo-systools.service"
  install -Dm644 "${startdir}/sysstates/zenbook-duo-systools-user.service" "${pkgdir}/usr/lib/systemd/user/zenbook-duo-systools-user.service"
  install -Dm755 "${startdir}/sysstates/zenbook-duo-systools.sleep" "${pkgdir}/usr/lib/systemd/system-sleep/zenbook-duo-systools"
  install -Dm644 "${startdir}/README.md" "${pkgdir}/usr/share/doc/zenbook-duo-systools/README.md"
  install -Dm644 "${startdir}/LICENSE" "${pkgdir}/usr/share/licenses/zenbook-duo-systools/LICENSE"
}

package_zenbook-duo-systools-fnkeys() {
  pkgdesc='ASUS Zenbook Duo Fn-key and detachable keyboard helper'
  depends=(bash bluez-utils glib2 inotify-tools kscreen libinput libnotify networkmanager python-pyusb qt6-tools sudo systemd usbutils)
  backup=(
    etc/zenbook-duo/fnkeys.conf
    etc/sudoers.d/zenbook-duo-systools-fnkeys
  )
  install=fnkeys/zenbook-duo-systools-fnkeys.install
  conflicts=(zenbook-duo-linux-systools-fnkeys)
  replaces=(zenbook-duo-linux-systools-fnkeys)
  provides=("zenbook-duo-linux-systools-fnkeys=${pkgver}")

  install -Dm755 "${startdir}/fnkeys/duo-fnkeys.sh" "${pkgdir}/usr/bin/zenbook-duo-systools-fnkeys"
  install -Dm644 "${startdir}/fnkeys/fnkeys.conf" "${pkgdir}/etc/zenbook-duo/fnkeys.conf"
  install -Dm440 "${startdir}/fnkeys/sudoers-zenbook-duo-systools-fnkeys" "${pkgdir}/etc/sudoers.d/zenbook-duo-systools-fnkeys"
  install -Dm644 "${startdir}/fnkeys/zenbook-duo-systools-fnkeys.service" "${pkgdir}/usr/lib/systemd/user/zenbook-duo-systools-fnkeys.service"
  install -Dm755 "${startdir}/fnkeys/backlight.py" "${pkgdir}/usr/lib/zenbook-duo-fnkeys/backlight.py"
  install -Dm644 "${startdir}/README.md" "${pkgdir}/usr/share/doc/zenbook-duo-systools-fnkeys/README.md"
  install -Dm644 "${startdir}/LICENSE" "${pkgdir}/usr/share/licenses/zenbook-duo-systools-fnkeys/LICENSE"
}
