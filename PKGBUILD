# Maintainer: Martin Zenker
pkgname=zenbook-duo-systools
pkgver=1.0.0
pkgrel=3
pkgdesc="System tools for Asus Zenbook Duo: keyboard backlight, display layout, and power profile"
arch=('x86_64' 'aarch64')
license=('custom')
depends=('bash' 'sudo' 'kscreen' 'power-profiles-daemon')
optdepends=('libnotify: notify-send notifications' 'networkmanager: nmcli (optional)')
backup=('etc/zenbook-duo/duo.conf')
install=zenbook-duo-systools.install

source=(
  "duo.sh"
  "duo.conf"
  "zenbook-duo-systools.service"
  "zenbook-duo-systools-user.service"
  "zenbook-duo-systools.sleep"
  "sudoers-zenbook-duo-systools"
  "zenbook-duo-systools.install"
)

sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')

package() {
  install -Dm755 "${srcdir}/duo.sh" "${pkgdir}/usr/bin/zenbook-duo-systools"
  install -Dm644 "${srcdir}/duo.conf" "${pkgdir}/etc/zenbook-duo/duo.conf"
  install -Dm644 "${srcdir}/zenbook-duo-systools.service" "${pkgdir}/usr/lib/systemd/system/zenbook-duo-systools.service"
  install -Dm644 "${srcdir}/zenbook-duo-systools-user.service" "${pkgdir}/usr/lib/systemd/user/zenbook-duo-systools-user.service"
  install -Dm755 "${srcdir}/zenbook-duo-systools.sleep" "${pkgdir}/usr/lib/systemd/system-sleep/zenbook-duo-systools"
  install -Dm440 "${srcdir}/sudoers-zenbook-duo-systools" "${pkgdir}/etc/sudoers.d/zenbook-duo-systools"
}
