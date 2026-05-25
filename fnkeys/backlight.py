#!/usr/bin/env python3
import os
import sys
import usb.core
import usb.util

VENDOR_ID = int(os.environ.get('DUO_VENDOR_ID', '0'), 16)
PRODUCT_ID = int(os.environ.get('DUO_PRODUCT_ID', '0'), 16)
REPORT_ID = 0x5A
WVALUE = 0x035A
WINDEX = 4
WLENGTH = 16

if VENDOR_ID == 0 or PRODUCT_ID == 0:
    print('Missing DUO_VENDOR_ID or DUO_PRODUCT_ID environment variables.')
    sys.exit(1)

if len(sys.argv) != 2:
    print(f'Usage: {sys.argv[0]} <level>')
    sys.exit(1)

try:
    level = int(sys.argv[1])
    if level < 0 or level > 3:
        raise ValueError
except ValueError:
    print('Invalid level. Must be an integer between 0 and 3.')
    sys.exit(1)

packet = [0] * WLENGTH
packet[0] = REPORT_ID
packet[1] = 0xBA
packet[2] = 0xC5
packet[3] = 0xC4
packet[4] = level


def find_device():
    return usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID)


def attach_kernel_driver(device):
    try:
        if device.is_kernel_driver_active(WINDEX):
            device.detach_kernel_driver(WINDEX)
            return True
    except Exception:
        pass
    return False


def main():
    dev = find_device()
    if dev is None:
        print(f'Device not found (Vendor ID: 0x{VENDOR_ID:04X}, Product ID: 0x{PRODUCT_ID:04X})')
        sys.exit(1)

    reattached = attach_kernel_driver(dev)
    try:
        ret = dev.ctrl_transfer(0x21, 0x09, WVALUE, WINDEX, packet, timeout=1000)
        if ret != WLENGTH:
            print(f'Warning: Only {ret} bytes sent out of {WLENGTH}.')
            sys.exit(1)
        print('Data packet sent successfully.')
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


if __name__ == '__main__':
    main()
