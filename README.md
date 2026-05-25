# zenbook-duo-linux-systools

This repository contains pure source code for ASUS Zenbook Duo helpers, separated into two clean directories:

- `sysstates/` — core system state helper scripts for display layout, backlight, and power-profile behavior.
- `fnkeys/` — optional Fn-key and keyboard attachment helper with an install helper script.

These scripts are intended for Arch-based Linux distributions and were developed under CachyOS with KDE Plasma Wayland.

## Versions

- `sysstates`: `0.9`
- `fnkeys`: `0.9`

## Directory layout

### `sysstates/`

Contains:

- `duo-sysstates.sh` — main helper script for display layouts, keyboard detection, backlight control, and power profile management.
- `duo-sysstates.conf` — default configuration for screens, rotations, keyboard matching, and backlight level.
- `setup-sysstates.sh` — installer for the core helper, config, sudoers policy, services, sleep hook, and prerequisites.
- `zenbook-duo-systools.service` — optional systemd service unit for power profile automation.
- `zenbook-duo-systools-user.service` — optional user service unit for display and backlight automation.
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

### Run the core helper

From the `sysstates/` directory:

```bash
cd sysstates
./duo-sysstates.sh apply
```

The script supports subcommands such as `display`, `rotate`, `light`, `power`, `lid`, `status`, `version`, and `help`.

### Install the core helper

From `sysstates/`:

```bash
cd sysstates
./setup-sysstates.sh
```

This installs `/usr/bin/zenbook-duo-systools`, `/etc/zenbook-duo/duo-sysstates.conf`, sudoers rules, systemd units, the sleep hook, and required packages.

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
- display rotation values
- keyboard match pattern
- Bluetooth keyboard fallback
- keyboard backlight percentage (`0-100`)
- X11-only window moving compatibility

Edit `fnkeys.conf` to adjust:

- main and lower screen names for `kscreen-doctor` or `gdctl`
- monitor scale
- KDE lower-display position
- feature ownership toggles for display, Wi-Fi, Bluetooth, and display-backlight sync
- main and lower backlight sysfs paths
- keyboard match pattern
- Bluetooth keyboard fallback
- detachable keyboard backlight level (`0-3`)

## Notes

The helpers are independent. You can install either helper on its own.
The setup scripts are tuned for Arch-like KDE Plasma Wayland systems such as CachyOS, using `kscreen-doctor` for display layout and `bluetoothctl` as the user-service keyboard detection fallback.
