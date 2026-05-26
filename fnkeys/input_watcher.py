#!/usr/bin/env python3
import os
import subprocess
import sys
import time

from evdev import InputDevice, ecodes, list_devices
from select import select

KEYBOARD_NAME = os.environ.get('FNKEYS_KEYBOARD_INPUT_NAME', 'ASUS Zenbook Duo Keyboard')
ABS_CODE = os.environ.get('FNKEYS_BACKLIGHT_EVENT_CODE', 'ABS_MISC')
UP_VALUE = int(os.environ.get('FNKEYS_BACKLIGHT_UP_VALUE', '16'))
DOWN_VALUE = int(os.environ.get('FNKEYS_BACKLIGHT_DOWN_VALUE', '199'))
DEBOUNCE_SECONDS = float(os.environ.get('FNKEYS_BACKLIGHT_EVENT_DEBOUNCE_SECONDS', '0.15'))
FNKEYS_HELPER = os.environ.get('FNKEYS_HELPER', '/usr/bin/zenbook-duo-systools-fnkeys')


def abs_code_number():
    try:
        return int(ABS_CODE)
    except ValueError:
        return getattr(ecodes, ABS_CODE, ecodes.ABS_MISC)


def run_helper(command):
    subprocess.run(
        [FNKEYS_HELPER, command],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def candidate_devices():
    target_code = abs_code_number()
    devices = []

    for path in list_devices():
        try:
            device = InputDevice(path)
            if device.name != KEYBOARD_NAME:
                device.close()
                continue
            capabilities = device.capabilities(absinfo=False)
            if target_code not in capabilities.get(ecodes.EV_ABS, []):
                device.close()
                continue
            devices.append(device)
        except PermissionError:
            print(f'Permission denied reading {path}; install the fnkeys input udev rule.', file=sys.stderr, flush=True)
        except OSError:
            continue

    return devices


def open_devices_until_available():
    logged_wait = False
    while True:
        devices = candidate_devices()
        if devices:
            paths = ', '.join(device.path for device in devices)
            print(
                f'Watching keyboard backlight events on: {paths} '
                f'(display-cycle={UP_VALUE}, keyboard-cycle={DOWN_VALUE})',
                flush=True,
            )
            return devices
        if not logged_wait:
            print(f'Waiting for input device named "{KEYBOARD_NAME}" with {ABS_CODE}.', flush=True)
            logged_wait = True
        time.sleep(2)


def main():
    target_code = abs_code_number()
    devices = open_devices_until_available()
    last_event_at = {}

    while True:
        readable, _, _ = select(devices, [], [], 2)
        if not readable:
            current_paths = {device.path for device in devices}
            new_devices = [device for device in candidate_devices() if device.path not in current_paths]
            for device in new_devices:
                devices.append(device)
            continue

        for device in readable:
            try:
                for event in device.read():
                    if event.type != ecodes.EV_ABS or event.code != target_code:
                        continue
                    if event.value == 0:
                        continue

                    now = time.monotonic()
                    if now - last_event_at.get(event.value, 0) < DEBOUNCE_SECONDS:
                        continue
                    last_event_at[event.value] = now

                    if event.value == UP_VALUE:
                        run_helper('display-brightness-cycle')
                    elif event.value == DOWN_VALUE:
                        run_helper('kbb-cycle')
            except OSError:
                try:
                    devices.remove(device)
                    device.close()
                except Exception:
                    pass
                if not devices:
                    devices = open_devices_until_available()


if __name__ == '__main__':
    main()
