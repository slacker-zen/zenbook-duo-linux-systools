# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Tauri V2 application for controlling ASUS Zenbook Duo keyboard backlight levels via **USB or Bluetooth**. The app uses:
- **Frontend**: SolidJS + TypeScript + Tailwind CSS v4 + Vite
- **Backend**: Rust with Tauri V2, rusb for USB communication, std::process for Bluetooth control via bluetoothctl

## Architecture

### USB Communication Flow
The app communicates directly with the ASUS Zenbook keyboard backlight controller using USB HID protocol:

1. **Device Initialization** (src-tauri/src/lib.rs:46-81):
   - Opens USB device with VID `0x0b05` and PID `0x1b2c` on startup
   - Detaches kernel driver if active on interface 4
   - Claims USB interface 4 for exclusive access
   - Device handle is stored in Tauri state (`UsbState`) as a Mutex for thread-safe access

2. **Backlight Control** (src-tauri/src/lib.rs:14-36):
   - `set_backlight` command accepts level 0-3 (off, low, mid, high)
   - Constructs HID report with magic bytes: `[0x5A, 0xBA, 0xC5, 0xC4, level, ...]`
   - Sends control transfer (type 0x21, request 0x09) to USB device
   - Timeout set to 1000ms per transfer

3. **Frontend Integration** (src/App.tsx):
   - SolidJS signals manage UI state and connection type (USB/Bluetooth)
   - Connection type selector allows switching between USB and Bluetooth modes
   - Tauri `invoke` API calls appropriate command based on connection type
   - Four buttons map to levels 0-3 with visual feedback via Tailwind classes
   - Status display shows connection type and operation result with color coding

### Bluetooth Communication Flow
The app can also control the keyboard backlight via Bluetooth GATT when the keyboard is connected wirelessly:

1. **Device Discovery** (src-tauri/src/lib.rs:51-72):
   - Runs `bluetoothctl devices` to find "ASUS Zenbook Duo Keyboard"
   - Extracts MAC address and converts format (AA:BB:CC:DD:EE:FF → AA_BB_CC_DD_EE_FF)
   - Returns error if device not found or not paired

2. **Bluetooth Backlight Control** (src-tauri/src/lib.rs:75-119):
   - `set_backlight_bluetooth` command accepts level 0-3 (off, low, mid, high)
   - Uses **same magic bytes** as USB: `[0xBA, 0xC5, 0xC4, level]`
   - Builds GATT path: `/org/bluez/hci0/dev_MAC/service001b/char003b`
   - Executes bluetoothctl commands via shell to select characteristic and write bytes
   - Parses stdout/stderr for error detection

3. **Key Differences from USB**:
   - No persistent device handle (discovers on each command)
   - Uses external process (bluetoothctl) instead of direct library
   - Requires BlueZ and bluetoothctl to be installed
   - Slightly higher latency due to device discovery + GATT write

### USB Permissions
The app requires USB access permissions. The `99-zenbook-backlight.rules` file is a udev rule that must be placed in `/etc/udev/rules.d/` to allow non-root access to the device. After placing the file, reload rules with:
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### Bluetooth Requirements
For Bluetooth mode:
- Keyboard must be paired with the system
- BlueZ and `bluetoothctl` must be installed (standard on most Linux distros)
- Device name must match: "ASUS Zenbook Duo Keyboard"

## Development Commands

### Setup
```bash
pnpm install
```

### Development
```bash
# Run in dev mode (starts Vite dev server + Tauri window)
pnpm tauri dev

# Or use npm script
pnpm dev  # Only starts Vite dev server, use 'pnpm tauri dev' instead
```

### Build
```bash
# Build frontend only
pnpm build

# Build full Tauri app
pnpm tauri build

# Run production preview
pnpm serve
```

### Tauri CLI
```bash
# Any Tauri command
pnpm tauri <command>
```

## Key Configuration

### Frontend (tauri.conf.json)
- Dev server runs on `http://localhost:1420`
- Before dev command: `pnpm dev` (Vite dev server)
- Before build command: `pnpm build`
- Frontend dist: `../dist`

### Backend (Cargo.toml)
- Library name: `zenbook_utils_lib` (avoids Windows naming conflicts)
- Crate types: `["staticlib", "cdylib", "rlib"]`
- Key dependencies: `rusb` for USB, `device_query` for device interaction

## Important Notes

### Connection Modes
- The app supports **dual-mode** operation: USB (wired) or Bluetooth (wireless)
- Use the connection type selector in the UI to switch between modes
- USB mode requires the keyboard to be physically connected
- Bluetooth mode requires the keyboard to be paired and in range

### USB Mode
- The app exits on startup if the USB device is not found or cannot be claimed
- Requires proper USB permissions (udev rules on Linux) - see `99-zenbook-backlight.rules`
- The device handle is managed as global state and must be accessed through the Mutex
- On Linux, may need to run with sudo or set up udev rules for USB access

### Bluetooth Mode
- Requires keyboard to be paired via Bluetooth settings first
- Uses bluetoothctl for GATT operations (standard on most Linux distros)
- Device discovery happens on each command (no persistent connection)
- Works with BlueZ stack on Linux

### Hardware Protocol
- Backlight levels are hardware-specific: 0=off, 1=low, 2=mid, 3=high
- Both USB and Bluetooth use the same magic bytes: `0xBA 0xC5 0xC4` + level
- GATT service: `service001b`, characteristic: `char003b`
