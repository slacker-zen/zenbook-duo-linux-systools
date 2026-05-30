# zenbook-duo-linux-systools

This repository contains ASUS Zenbook Duo helpers built around a single user-session event matrix:

- `coordinator/` — event matrix coordinator that owns the user-session event loop and dispatches to helper commands only on state changes.
- `control/` — stable command/API layer for tray and UI clients; exposes JSON status/config and forwards actions to the helpers.
- `ui/` — active tray utility and configuration UI.
- `sysstates/` — core system state helper scripts for display layout, backlight, and power-profile behavior.
- `fnkeys/` — Fn-key, input-event, USB HID, Bluetooth GATT, and notification helper scripts.
- `3rd_src/` — preserved upstream/ancestor source trees that are kept for reference but are not the active development surface.

These scripts are intended for Arch-based Linux distributions and were developed under CachyOS with KDE Plasma Wayland.

## Versions

- `sysstates`: `1.1`
- `fnkeys`: `1.2`
- `matrix`: `1.0`

## Directory layout

### `sysstates/`

Contains:

- `duo-sysstates.sh` — main helper script for display layouts, keyboard detection, backlight control, and power profile management.
- `duo-sysstates.conf` — default configuration for screens, rotations, docked keyboard detection, and backlight level.
- `setup-sysstates.sh` — installer for the core helper, config, sudoers policy, services, sleep hook, and prerequisites.
- `zenbook-duo-systools.service` — optional systemd service unit for power profile automation and lid-close sleep policy.
- `zenbook-duo-systools.sleep` — optional system-sleep hook to reapply settings after resume.
- `sudoers-zenbook-duo-systools` — sudoers helper config for safe backlight control.

### `fnkeys/`

Contains:

- `duo-fnkeys.sh` — Fn-key helper script for keyboard attachment detection and backlight handling.
- `fnkeys.conf` — standalone Fn-key helper configuration.
- `backlight.py` — USB and Bluetooth GATT keyboard backlight helper.
- `input_watcher.py` — evdev watcher for the physical keyboard backlight up/down keys.
- `72-zenbook-duo-fnkeys-input.rules` — udev rule that lets the active user service read the keyboard input node.
- `setup-fnkeys.sh` — optional prerequisite installer for the Fn-key helper.
- `sudoers-zenbook-duo-systools-fnkeys` — sudoers helper config for Fn-key backlight control.

### `coordinator/`

Contains:

- `zenbook-duo-matrix.sh` — single user-session coordinator for USB, Bluetooth, polling, and physical Fn-key input events.
- `zenbook-duo-matrix.service` — user-session service unit for the coordinator.

### `control/`

Contains:

- `zenbook-duo-control.sh` — UI/control boundary used by tray utilities and other clients. It reads status as JSON, lists and writes both helper configs, and forwards actions to the matrix, sysstates, and fnkeys helpers.

### `ui/`

Contains:

- Tauri/Solid tray utility source. This is the active UI development path and talks to `control/zenbook-duo-control.sh` instead of calling matrix, sysstates, or fnkeys directly.

### `3rd_src/`

Contains:

- `asus-zenbookduo/` and `zenbook-utils/` upstream/ancestor source trees. These remain available for reference while the active project code evolves in the root-level helper and UI directories.

## Runtime Boundary

Runtime follows this rule:

- installation, configuration, sudoers policy, and shared helper binaries are system-wide
- power and sleep behavior run through the system service
- KDE/Wayland display layout, notifications, USB/Bluetooth keyboard transport, and physical Fn-key behavior run through the single user-session matrix service

This boundary is intentional. KDE/Wayland display control belongs to the active logged-in session, while privileged writes are limited to installed sudoers policies and narrow helper commands.

## Usage

### Build Package

On Arch/CachyOS, from the repository root:

```bash
makepkg -f
```

This builds one pacman package:

- `zenbook-duo-systools`

The package metadata conflicts with and replaces the earlier split package names. The install script removes old hand-made `duo` service entries and disables the older duplicate user services.

On Zorin/Ubuntu-family distributions, build a Debian package instead:

```bash
./packaging/debian/build-deb.sh --install-prereqs
```

This creates:

- `dist/zenbook-duo-systools_1.3-10_amd64.deb`

Install it with:

```bash
sudo apt install ./dist/zenbook-duo-systools_1.3-10_amd64.deb
```

The Debian package declares the equivalent apt dependencies for BlueZ, KDE kscreen, notifications, Python evdev/PyUSB, systemd, WebKit/GTK, and the tray UI runtime. The Arch `PKGBUILD` remains the CachyOS/Arch package path.

### Run the core helper

From the `sysstates/` directory:

```bash
cd sysstates
./duo-sysstates.sh apply
```

The script supports subcommands such as `display`, `rotate`, `light`, `power`, `lid`, `status`, `version`, and `help`.
Its `watch` command is legacy; the matrix service should own user-session event watching.

### Install the core helper

From `sysstates/`:

```bash
cd sysstates
./setup-sysstates.sh
```

This installs `/usr/bin/zenbook-duo-systools`, `/etc/zenbook-duo/duo-sysstates.conf`, sudoers rules, the system power/lid unit, the sleep hook, and required packages.
The setup script detects Arch/CachyOS versus Zorin/Ubuntu/Debian and installs prerequisites with `pacman` or `apt-get` accordingly.

The system service also owns the lid-close policy. It inhibits logind's default lid handling while active, switches keyboard backlight off first, then suspends while charging/on AC or hibernates while discharging/on battery:

```bash
sudo systemctl enable --now zenbook-duo-systools.service
```

### Run the matrix

From the repository root:

```bash
./coordinator/zenbook-duo-matrix.sh status
```

The matrix supports `service`, `reconcile`, `status`, `version`, and `help`.

### Run the control layer

From the repository root:

```bash
./control/zenbook-duo-control.sh status --json
./control/zenbook-duo-control.sh config list --json
./control/zenbook-duo-control.sh display brightness --json
./control/zenbook-duo-control.sh display brightness step main 10
./control/zenbook-duo-control.sh display brightness step lower 10
./control/zenbook-duo-control.sh action matrix reconcile
./control/zenbook-duo-control.sh action sysstates display detached
```

The tray/UI should call this control layer instead of calling the individual helper scripts directly.

### Run the Fn-key helper directly

From the `fnkeys/` directory:

```bash
cd fnkeys
./duo-fnkeys.sh notify-test
```

### Install the package

On Arch/CachyOS, from the repository root after `makepkg -f`:

```bash
sudo pacman -R --noconfirm zenbook-duo-systools-fnkeys
sudo pacman -U --noconfirm zenbook-duo-systools-1.3-10-x86_64.pkg.tar.zst
```

If you previously used the setup script before `input_watcher.py` was packaged, pacman may report that `/usr/lib/zenbook-duo-fnkeys/input_watcher.py` exists in the filesystem. That stale helper is not package-owned; upgrade with:

```bash
sudo pacman -R --noconfirm zenbook-duo-systools-fnkeys
sudo pacman -U --overwrite usr/lib/zenbook-duo-fnkeys/input_watcher.py zenbook-duo-systools-1.3-10-x86_64.pkg.tar.zst
```

On Zorin/Ubuntu-family distributions, from the repository root after `./packaging/debian/build-deb.sh --install-prereqs`:

```bash
sudo apt install ./dist/zenbook-duo-systools_1.3-10_amd64.deb
```

The matrix service should be the only user-session owner of display and keyboard events. Keep the system `zenbook-duo-systools.service` enabled for lid/power policy, but disable the older user watchers when using the matrix:

```bash
sudo systemctl enable --now zenbook-duo-systools.service
systemctl --user disable --now zenbook-duo-systools-user.service zenbook-duo-systools-fnkeys.service
systemctl --user enable --now zenbook-duo-matrix.service
```

## Configuration

The action helpers use separate configs, and the matrix reads both:

- `sysstates/duo-sysstates.conf` installs to `/etc/zenbook-duo/duo-sysstates.conf`
- `fnkeys/fnkeys.conf` installs to `/etc/zenbook-duo/fnkeys.conf`

Edit `duo-sysstates.conf` to adjust:

- main and lower screen names
- KDE lower-display position
- display rotation values
- direct dock USB path and keyboard match pattern
- keyboard backlight percentage (`0-100`)
- Fnkeys helper path used to switch the detachable keyboard backlight off on lid close
- lid state path and polling interval
- opt-in display attach/detach layout switching
- Plasma/KWin refresh behavior after display layout changes
- Plasma panel/taskbar screen assignment for attached and detached modes
- watcher debounce delay for USB dock/undock events
- X11-only window moving compatibility

Edit `fnkeys.conf` to adjust:

- main and lower screen names for `kscreen-doctor` or `gdctl`
- monitor scale
- KDE lower-display position
- feature ownership toggles for display, Wi-Fi, Bluetooth, and display-backlight sync
- attached-mode Bluetooth preservation for Fn/media transport
- forced-off Bluetooth handling, where dock USB becomes the only fallback
- Plasma/KWin refresh behavior after display layout changes
- Plasma panel/taskbar screen assignment for attached and detached modes
- main and lower backlight sysfs paths
- direct dock USB path and keyboard match pattern
- Bluetooth keyboard identity, GATT backlight characteristic, and attached-mode Bluetooth preservation for Fn/media transport
- detachable keyboard backlight level (`0-3`)
- physical keyboard backlight key event watching (`ABS_MISC` values `16` and `199` by default), enabled transports, and display brightness cycle step
- matrix coordinator toggles for USB, Bluetooth, display ownership, keyboard-backlight reapply, and low-rate polling

The packaged default is `FNKEYS_BACKLIGHT_LEVEL=2`. The matrix reapplies that level when keyboard transport changes to a present keyboard. If `/etc/zenbook-duo/fnkeys.conf` already exists from an older install, update that file or merge the package `.pacnew` so it also contains `FNKEYS_BACKLIGHT_LEVEL=2`.

Bluetooth backlight control uses BlueZ GATT through `bluetoothctl`, matching the preserved `3rd_src/zenbook-utils` implementation. If Bluetooth writes fail while the keyboard is connected, set `ExportClaimedServices = read-write` under `[GATT]` in `/etc/bluetooth/main.conf`, then restart Bluetooth.

The physical backlight level keys on the detachable keyboard are proprietary ASUS input events, not standard key codes. The fnkeys package watches the `ASUS Zenbook Duo Keyboard` input node for `EV_ABS/ABS_MISC`; observed defaults are `16` for the physical backlight-up key and `199` for the physical backlight-down key. The backlight-down key cycles the keyboard backlight through levels `0-3` and shows the new value. The backlight-up key cycles both `eDP-1` and `eDP-2` display brightness in `20%` steps, wrapping from `100%` back to `20%`, and shows the calculated brightness step and target value. Notification delivery falls back to the user session bus at `$XDG_RUNTIME_DIR/bus` so physical-key notifications still work when the user service does not inherit `DBUS_SESSION_BUS_ADDRESS`.

Minor boot issue corrected: the fnkeys user service reapplies the configured detachable keyboard backlight during startup/boot and after resume, so the keyboard should return to the configured `FNKEYS_BACKLIGHT_LEVEL` without pressing a physical backlight key.

USB cradle note: a detached keyboard connected by ordinary USB appears as `0b05:1b2c`, but it is still treated as `detached` unless it is on the configured dock path. USB and Bluetooth watcher events are filtered through the physical dock-mode state, so a cradle connection should not repeatedly reapply display layout or USB backlight setup.

The event matrix derives state first, then dispatches:

- `physical_mode`: `attached` when the keyboard is on the configured dock path, otherwise `detached`
- `transport`: `dock_usb`, `cradle_usb`, `bluetooth`, or `absent`
- display layout is applied only when `physical_mode` changes
- keyboard backlight is reapplied only when transport changes to a present keyboard
- physical backlight keys are still handled through the evdev watcher and invoke the narrow fnkeys subcommands
- by default the physical `ABS_MISC` watcher only runs for `transport=bluetooth`; ordinary USB cradle transport does not expose the same proprietary event path and is skipped to avoid idle polling

## Notes

The package is unified, but the helper commands remain narrow and testable. The setup scripts are kept for development/manual installs; the Arch package is the preferred installation path.

For `sysstates`, `attached` means the keyboard is connected through the built-in dock connector. On this model that connector appears as `/sys/bus/usb/devices/3-6`. Bluetooth and a normal USB cable can make the keyboard usable, but they still count as `detached` because the lower screen is not physically covered.

On KDE Plasma Wayland, panels and some windows can remain associated with the lower display after `eDP-2` is disabled. The helpers keep Plasma refresh hooks disabled by default because some Plasma sessions can briefly lose the desktop shell during a refresh. If the taskbar still stays on the disabled lower display, first try `REFRESH_PLASMA_ON_LAYOUT=true`; if that is not enough, set `RESTART_PLASMA_ON_ATTACH=true` in `duo-sysstates.conf` or `FNKEYS_RESTART_PLASMA_ON_ATTACH=true` in `fnkeys.conf` for the stronger fallback.

By default, the helpers move Plasma panels to screen `0` in attached mode and screen `1` in detached mode. On the tested KDE layout, screen `0` is `eDP-1` and screen `1` is `eDP-2`. Adjust `PLASMA_PANEL_SCREEN_ATTACHED` and `PLASMA_PANEL_SCREEN_DETACHED` if your Plasma screen numbering differs.

The top-row key behavior can change with the keyboard connection mode and BIOS Fn-lock state. This behavior is provided by firmware/kernel/desktop input handling, not by `duo-fnkeys.sh`; the helper does not remap `F1`, `F2`, `F3`, mute, or volume keys. Observed behavior on this model:

- when the keyboard is detached, `F1`, `F2`, and `F3` act as media keys: volume mute, volume down, and volume up
- when the keyboard is detached, `Fn` + `F1`, `Fn` + `F2`, and so on act as real `F1`, `F2`, and so on
- when the keyboard is directly attached on the dock connector, the USB keyboard interface emits real `F1`, `F2`, and so on
- when directly attached, the keyboard can still keep a Bluetooth connection for Fn/media transport, so the Fn-key helper keeps Bluetooth unblocked in attached mode by default
- the detachable keyboard backlight is set through kernel LED sysfs when available, USB HID when docked/wired, and the BlueZ GATT characteristic when only Bluetooth is connected
- the detachable keyboard backlight keys are handled through the fnkeys evdev watcher, using the packaged udev rule to let the active user service read the input node; by default one key cycles keyboard backlight levels and the other cycles both display backlights in 20% steps
- if the user explicitly blocks Bluetooth, the Fn-key helper respects that and falls back to dock USB only; in that mode the keyboard must be physically attached for regular function-key behavior

Fn-lock settings in the BIOS can invert or normalize this behavior, so check that setting if the top row does not match the expected mode.

## Credits
See [credits.md](./3rd_src/credits.md)
