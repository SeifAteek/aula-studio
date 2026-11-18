#!/usr/bin/env python3
"""Read-only monitor. Polls feature report 7 and logs vendor input report 3.

It never sends a report. Input reports 1, 2, 4, 5 and 6 carry keystrokes or media keys, so they
are dropped without being stored or printed.
"""
import ctypes as C
import sys
import time

from aula import device

VENDOR_INPUT_REPORT = 3
FEATURE_REPORT_TYPE = 2  # kIOHIDReportTypeFeature
CONFIG_REPORT_ID = 7


def should_log(report_id):
    return report_id == VENDOR_INPUT_REPORT


assert should_log(3) and not any(should_log(r) for r in (1, 2, 4, 5, 6, 7))

io, cf, P = device._iokit, device._cf, device._P
CALLBACK = C.CFUNCTYPE(None, P, C.c_int32, P, C.c_uint32, C.c_uint32, C.POINTER(C.c_uint8), C.c_long)
io.IOHIDDeviceGetReport.restype = C.c_int32
io.IOHIDDeviceGetReport.argtypes = [P, C.c_uint32, C.c_long, P, C.POINTER(C.c_long)]
io.IOHIDDeviceRegisterInputReportCallback.restype = None
io.IOHIDDeviceRegisterInputReportCallback.argtypes = [P, P, C.c_long, CALLBACK, P]
io.IOHIDDeviceScheduleWithRunLoop.restype = None
io.IOHIDDeviceScheduleWithRunLoop.argtypes = [P, P, P]
cf.CFRunLoopGetCurrent.restype = P
cf.CFRunLoopRunInMode.restype = C.c_int32
cf.CFRunLoopRunInMode.argtypes = [P, C.c_double, C.c_bool]


def stamp():
    return time.strftime("%H:%M:%S")


def on_input(_context, _result, _sender, _type, report_id, report, length):
    if should_log(report_id):
        print(f"{stamp()} vendor input report {report_id}: {bytes(report[:length]).hex(' ').upper()}", flush=True)


def read_feature(dev):
    buffer = (C.c_uint8 * device.protocol.PACKET_SIZE)()
    length = C.c_long(len(buffer))
    rc = io.IOHIDDeviceGetReport(dev, FEATURE_REPORT_TYPE, CONFIG_REPORT_ID, buffer, C.byref(length)) & 0xFFFFFFFF
    return f"error {rc:#010x}" if rc else bytes(buffer[:length.value]).hex(" ").upper()


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    if not 1 <= seconds <= 600:
        sys.exit("usage: read_monitor.py [seconds from 1 to 600]")
    dev, _manager, _devices = device._config_interface()
    rc = io.IOHIDDeviceOpen(dev, 0) & 0xFFFFFFFF
    if rc:
        sys.exit(f"Could not open the keyboard (IOReturn {rc:#010x}).")
    input_buffer = (C.c_uint8 * 8)()
    callback = CALLBACK(on_input)
    mode = P.in_dll(cf, "kCFRunLoopDefaultMode")
    io.IOHIDDeviceRegisterInputReportCallback(dev, input_buffer, len(input_buffer), callback, None)
    io.IOHIDDeviceScheduleWithRunLoop(dev, cf.CFRunLoopGetCurrent(), mode)
    last = read_feature(dev)
    print(f"{stamp()} feature report 7 baseline: {last}", flush=True)
    print(f"Monitoring for {seconds} seconds. Keystrokes are ignored.", flush=True)
    end = time.monotonic() + seconds
    try:
        while time.monotonic() < end:
            cf.CFRunLoopRunInMode(mode, 0.2, False)
            current = read_feature(dev)
            if current != last:
                print(f"{stamp()} feature report 7 changed: {last} -> {current}", flush=True)
                last = current
    finally:
        io.IOHIDDeviceClose(dev, 0)
    print(f"{stamp()} Monitoring finished. Final feature report 7: {last}", flush=True)


if __name__ == "__main__":
    main()
