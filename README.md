# zenbook-duo-systools

A small Arch package and helper script for ASUS Zenbook Duo devices.

This repository contains:

- `src/duo.sh` — the main helper script.
- `src/duo.conf` — default configuration for screen IDs and rotation.
- Systemd service units and a system-sleep hook for automatic behavior.
- `PKGBUILD` for building the Arch package.

## Purpose

The helper script manages Zenbook Duo display behavior, keyboard backlight, and power profile behavior based on keyboard attachment and AC/battery state.

## Actions

### `apply`

Runs the full configured workflow:

- Sets keyboard backlight to the configured percent.
- Applies the correct power profile for AC or battery.
- Detects whether the keyboard is attached and applies the matching display layout.

### `display [auto|attached|detached]`

Applies the display layout for the selected mode.

- `auto` detects keyboard attachment and chooses `attached` or `detached` automatically.
- `attached` enables the main display and turns off the lower screen.
- `detached` enables both the main and lower screens.

### `rotate <main|lower|both> <rotation>`

Updates the configured rotation values and reapplies the display layout.

- `main` changes rotation for `eDP-1`.
- `lower` changes rotation for `eDP-2`.
- `both` changes both screens.

Supported rotations:

- `normal`
- `left`
- `right`
- `inverted`

### `light`

Sets the keyboard backlight brightness according to the configured percent.

### `power`

Selects the power profile based on current AC/battery state.

- `performance` when on AC power.
- `balanced` (or `power-saver` fallback) when on battery.

### `lid`

Handles lid close behavior:

- Suspends when on AC power.
- Hibernates when on battery.

### `status`

Displays the current keyboard state and configured screen setup.

### `help`

Shows the usage help text.

## Configuration

The default configuration lives in `/etc/zenbook-duo/duo.conf`.

Defaults:

- `MAIN_SCREEN="eDP-1"`
- `LOWER_SCREEN="eDP-2"`
- `MAIN_ROTATION="normal"`
- `LOWER_ROTATION="normal"`
- `KEYBOARD_MATCH="Keyboard|ASUS|ASUSTeK|AT Translated Set 2 keyboard"`
- `BACKLIGHT_LEVEL_PERCENT=50`

## Systemd integration

This repo includes:

- `src/zenbook-duo-systools.service` — system service for power profile management.
- `src/zenbook-duo-systools-user.service` — user service for display and backlight automation.
- `src/zenbook-duo-systools.sleep` — system-sleep hook that reapplies settings after resume.

## Building

Build the package with `makepkg -f` from the repository root.

## Notes

- The script prefers `kscreen-doctor` if available, and falls back to `xrandr`.
- Window repositioning uses `wmctrl` and `xrandr` when available.
- The package installs a sudoers policy for keyboard brightness control.
