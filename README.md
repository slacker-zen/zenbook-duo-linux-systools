# zenbook-duo-linux-systools

This repository contains pure source code for ASUS Zenbook Duo helpers, separated into two clean directories:

- `sysstates/` — core system state helper scripts for display layout, backlight, and power-profile behavior.
- `fnkeys/` — optional Fn-key and keyboard attachment helper with an install helper script.

These scripts are intended for Arch-based Linux distributions and were developed under CachyOS with KDE Plasma Wayland.

## Versions

- `sysstates`: `1.0`
- `fnkeys`: `1.1`

## Directory layout

### `sysstates/`

Contains:

- `duo-sysstates.sh` — main helper script for display layouts, keyboard detection, backlight control, and power profile management.
- `duo-sysstates.conf` — default configuration for screens, rotations, docked keyboard detection, and backlight level.
- `setup-sysstates.sh` — installer for the core helper, config, sudoers policy, services, sleep hook, and prerequisites.
- `zenbook-duo-systools.service` — optional systemd service unit for power profile automation.
- `zenbook-duo-systools-user.service` — optional user service unit that watches keyboard dock/undock events and applies display layouts.
- `zenbook-duo-systools.sleep` — optional system-sleep hook to reapply settings after resume.
- `sudoers-zenbook-duo-systools` — sudoers helper config for safe backlight control.

### `fnkeys/`

Contains:

- `duo-fnkeys.sh` — Fn-key helper script for keyboard attachment detection and backlight handling.
- `fnkeys.conf` — standalone Fn-key helper configuration.
- `zenbook-duo-systools-fnkeys.service` — optional user service unit for Fn-key, USB, and Bluetooth keyboard events.
- `setup-fnkeys.sh` — optional prerequisite installer for the Fn-key helper.
- `sudoers-zenbook-duo-systools-fnkeys` — sudoers helper config for Fn-key backlight control.

## Runtime Boundary

Both helpers follow the same rule:

- installation, configuration, sudoers policy, and shared helper binaries are system-wide
- power and sleep behavior are system-level
- KDE/Wayland display layout, notifications, and keyboard-session behavior run as user services

This split is intentional. KDE/Wayland display control belongs to the active logged-in session, while privileged writes are limited to the installed sudoers policies.

## Usage

### Build packages

From the repository root:

```bash
makepkg -f
```

This builds:

- `zenbook-duo-systools`
- `zenbook-duo-systools-fnkeys`

The package metadata declares conflicts and replacements for earlier split package names. The install scripts remove old hand-made `duo` service entries before installing the packaged helpers.

### Run the core helper

From the `sysstates/` directory:

```bash
cd sysstates
./duo-sysstates.sh apply
```

The script supports subcommands such as `display`, `rotate`, `light`, `power`, `lid`, `status`, `version`, and `help`.
Use `watch` to keep the helper running in the user session and react to USB dock/undock events.

### Install the core helper

From `sysstates/`:

```bash
cd sysstates
./setup-sysstates.sh
```

This installs `/usr/bin/zenbook-duo-systools`, `/etc/zenbook-duo/duo-sysstates.conf`, sudoers rules, systemd units, the sleep hook, and required packages.
The user service runs `zenbook-duo-systools watch`, so restart it after package upgrades or config changes:

```bash
systemctl --user restart zenbook-duo-systools-user.service
```

### Run the Fn-key helper

From the `fnkeys/` directory:

```bash
cd fnkeys
./duo-fnkeys.sh
```

### Install Fn-key prerequisites

From `fnkeys/`:

```bash
cd fnkeys
./setup-fnkeys.sh
```

This installs `/usr/bin/zenbook-duo-systools-fnkeys`, `/etc/zenbook-duo/fnkeys.conf`, the USB backlight helper, sudoers rules, the user service unit, and required packages.

## Configuration

The helpers are intentionally independent and use separate configs:

- `sysstates/duo-sysstates.conf` installs to `/etc/zenbook-duo/duo-sysstates.conf`
- `fnkeys/fnkeys.conf` installs to `/etc/zenbook-duo/fnkeys.conf`

Edit `duo-sysstates.conf` to adjust:

- main and lower screen names
- KDE lower-display position
- display rotation values
- direct dock USB path and keyboard match pattern
- keyboard backlight percentage (`0-100`)
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

The packaged default is `FNKEYS_BACKLIGHT_LEVEL=2`. The fnkeys user service applies that level on startup, after resume/boot commands, and whenever the docked USB keyboard attach event is observed. If `/etc/zenbook-duo/fnkeys.conf` already exists from an older install, update that file or merge the package `.pacnew` so it also contains `FNKEYS_BACKLIGHT_LEVEL=2`.

Bluetooth backlight control uses BlueZ GATT through `bluetoothctl`, matching the working `zenbook-utils` implementation. If Bluetooth writes fail while the keyboard is connected, set `ExportClaimedServices = read-write` under `[GATT]` in `/etc/bluetooth/main.conf`, then restart Bluetooth.

## Notes

The helpers are independent. You can install either helper on its own.
The setup scripts are tuned for Arch-like KDE Plasma Wayland systems such as CachyOS, using `kscreen-doctor` for display layout.

For `sysstates`, `attached` means the keyboard is connected through the built-in dock connector. On this model that connector appears as `/sys/bus/usb/devices/3-6`. Bluetooth and a normal USB cable can make the keyboard usable, but they still count as `detached` because the lower screen is not physically covered.

On KDE Plasma Wayland, panels and some windows can remain associated with the lower display after `eDP-2` is disabled. The helpers keep Plasma refresh hooks disabled by default because some Plasma sessions can briefly lose the desktop shell during a refresh. If the taskbar still stays on the disabled lower display, first try `REFRESH_PLASMA_ON_LAYOUT=true`; if that is not enough, set `RESTART_PLASMA_ON_ATTACH=true` in `duo-sysstates.conf` or `FNKEYS_RESTART_PLASMA_ON_ATTACH=true` in `fnkeys.conf` for the stronger fallback.

By default, the helpers move Plasma panels to screen `0` in attached mode and screen `1` in detached mode. On the tested KDE layout, screen `0` is `eDP-1` and screen `1` is `eDP-2`. Adjust `PLASMA_PANEL_SCREEN_ATTACHED` and `PLASMA_PANEL_SCREEN_DETACHED` if your Plasma screen numbering differs.

The top-row key behavior can change with the keyboard connection mode and BIOS Fn-lock state. This behavior is provided by firmware/kernel/desktop input handling, not by `duo-fnkeys.sh`; the helper does not remap `F1`, `F2`, `F3`, mute, or volume keys. Observed behavior on this model:

- when the keyboard is detached, `F1`, `F2`, and `F3` act as media keys: volume mute, volume down, and volume up
- when the keyboard is detached, `Fn` + `F1`, `Fn` + `F2`, and so on act as real `F1`, `F2`, and so on
- when the keyboard is directly attached on the dock connector, the USB keyboard interface emits real `F1`, `F2`, and so on
- when directly attached, the keyboard can still keep a Bluetooth connection for Fn/media transport, so the Fn-key helper keeps Bluetooth unblocked in attached mode by default
- the detachable keyboard backlight is set through kernel LED sysfs when available, USB HID when docked/wired, and the BlueZ GATT characteristic when only Bluetooth is connected
- if the user explicitly blocks Bluetooth, the Fn-key helper respects that and falls back to dock USB only; in that mode the keyboard must be physically attached for regular function-key behavior

Fn-lock settings in the BIOS can invert or normalize this behavior, so check that setting if the top row does not match the expected mode.
