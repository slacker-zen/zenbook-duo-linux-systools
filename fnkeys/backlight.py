#!/usr/bin/env python3
import os
import subprocess
import sys

import usb.core
import usb.util

REPORT_ID = 0x5A
WVALUE = 0x035A
WINDEX = 4
WLENGTH = 16
PAYLOAD = (0xBA, 0xC5, 0xC4)
BLUEZ_MAIN_CONF = '/etc/bluetooth/main.conf'


def usage():
    print(f'Usage: {sys.argv[0]} <level>')
    print(f'       {sys.argv[0]} usb <vendor-id> <product-id> <level>')
    print(f'       {sys.argv[0]} bluetooth <gatt-characteristic-path> <level>')
    sys.exit(1)


def parse_level(value):
    try:
        level = int(value)
        if level < 0 or level > 3:
            raise ValueError
    except ValueError:
        print('Invalid level. Must be an integer between 0 and 3.')
        sys.exit(1)
    return level


def parse_hex(value, label):
    try:
        return int(value, 16)
    except ValueError:
        print(f'Invalid {label}: {value}')
        sys.exit(1)


def attach_kernel_driver(device):
    try:
        if device.is_kernel_driver_active(WINDEX):
            device.detach_kernel_driver(WINDEX)
            return True
    except Exception:
        pass
    return False


def set_usb_backlight(vendor_id, product_id, level):
    packet = [0] * WLENGTH
    packet[0] = REPORT_ID
    packet[1:4] = PAYLOAD
    packet[4] = level

    dev = usb.core.find(idVendor=vendor_id, idProduct=product_id)
    if dev is None:
        print(f'Device not found (Vendor ID: 0x{vendor_id:04X}, Product ID: 0x{product_id:04X})')
        sys.exit(1)

    reattached = attach_kernel_driver(dev)
    try:
        ret = dev.ctrl_transfer(0x21, 0x09, WVALUE, WINDEX, packet, timeout=1000)
        if ret != WLENGTH:
            print(f'Warning: Only {ret} bytes sent out of {WLENGTH}.')
            sys.exit(1)
        print('USB data packet sent successfully.')
    except usb.core.USBError as e:
        print(f'Control transfer failed: {e}')
        sys.exit(1)
    finally:
        try:
            usb.util.release_interface(dev, WINDEX)
        except Exception:
            pass
        if reattached:
            try:
                dev.attach_kernel_driver(WINDEX)
            except Exception:
                pass


def set_bluetooth_backlight(characteristic_path, level):
    if not bluez_exports_claimed_services_read_write():
        print(
            'Bluetooth GATT writes need ExportClaimedServices = read-write '
            f'under [GATT] in {BLUEZ_MAIN_CONF}; restart bluetooth after changing it.'
        )
        sys.exit(1)

    write_value = ' '.join(f'0x{byte:02x}' for byte in (*PAYLOAD, level))
    commands = (
        f'gatt.select-attribute {characteristic_path}\n'
        f'gatt.write "{write_value}"\n'
        'quit\n'
    )
    result = subprocess.run(
        ['bluetoothctl'],
        check=False,
        text=True,
        input=commands,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output = '\n'.join(part for part in (result.stdout.strip(), result.stderr.strip()) if part)
    if result.returncode != 0 or 'Failed' in output or 'Error' in output or 'not available' in output:
        print(output or 'Bluetooth GATT write failed.')
        sys.exit(result.returncode or 1)
    if 'Attempting to write' not in output:
        print(output or 'Bluetooth GATT write may not have executed.')
        sys.exit(result.returncode)
    print('Bluetooth data packet sent successfully.')


def bluez_exports_claimed_services_read_write():
    try:
        with open(BLUEZ_MAIN_CONF, encoding='utf-8') as config:
            in_gatt = False
            for raw_line in config:
                line = raw_line.strip()
                if not line or line.startswith('#'):
                    continue
                if line.startswith('[') and line.endswith(']'):
                    in_gatt = line.lower() == '[gatt]'
                    continue
                if in_gatt and line.lower().replace(' ', '') == 'exportclaimedservices=read-write':
                    return True
    except OSError:
        return False
    return False


def main():
    if len(sys.argv) == 2:
        vendor_id = parse_hex(os.environ.get('DUO_VENDOR_ID', '0'), 'DUO_VENDOR_ID')
        product_id = parse_hex(os.environ.get('DUO_PRODUCT_ID', '0'), 'DUO_PRODUCT_ID')
        if vendor_id == 0 or product_id == 0:
            print('Missing DUO_VENDOR_ID or DUO_PRODUCT_ID environment variables.')
            sys.exit(1)
        set_usb_backlight(vendor_id, product_id, parse_level(sys.argv[1]))
        return

    if len(sys.argv) == 5 and sys.argv[1] == 'usb':
        vendor_id = parse_hex(sys.argv[2], 'vendor id')
        product_id = parse_hex(sys.argv[3], 'product id')
        set_usb_backlight(vendor_id, product_id, parse_level(sys.argv[4]))
        return

    if len(sys.argv) == 4 and sys.argv[1] == 'bluetooth':
        set_bluetooth_backlight(sys.argv[2], parse_level(sys.argv[3]))
        return

    usage()


if __name__ == '__main__':
    main()
