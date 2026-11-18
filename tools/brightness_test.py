#!/usr/bin/env python3
"""Lighting write test. Dry run by default; sends one validated lighting packet only with --send."""
import ctypes as C
import ctypes.util
import sys

VID, PID = 0x1A2C, 0x9EF4
# report 7, FF FF, effect 0B (Fixed on), brightness 02 (40%), speed 01, mode 00, 00
DEFAULT_PACKET = "07FFFF0B02010000"
OUTPUT_REPORT = 1  # kIOHIDReportTypeOutput


def is_lighting_packet(p):
    """Allow only the documented lighting format, so no other command can be sent by mistake."""
    return (len(p) == 8 and p[:3] == b"\x07\xff\xff" and p[3] <= 0x13 and p[4] <= 5
            and p[5] <= 2 and p[6] <= 1 and p[7] == 0)


assert is_lighting_packet(bytes.fromhex(DEFAULT_PACKET))
assert is_lighting_packet(bytes.fromhex("07FFFF0202000000"))
assert not is_lighting_packet(bytes.fromhex("07F0AA0000000000"))  # settings restore must stay blocked
assert not is_lighting_packet(bytes.fromhex("07FFFF1402000000"))  # effect out of range

iokit = C.CDLL(ctypes.util.find_library("IOKit"))
cf = C.CDLL(ctypes.util.find_library("CoreFoundation"))
P = C.c_void_p
for fn, res, args in [
    (cf.CFStringCreateWithCString, P, [P, C.c_char_p, C.c_uint32]),
    (cf.CFNumberCreate, P, [P, C.c_long, P]),
    (cf.CFNumberGetValue, C.c_bool, [P, C.c_long, P]),
    (cf.CFDictionaryCreateMutable, P, [P, C.c_long, P, P]),
    (cf.CFDictionarySetValue, None, [P, P, P]),
    (cf.CFSetGetCount, C.c_long, [P]),
    (cf.CFSetGetValues, None, [P, P]),
    (iokit.IOHIDManagerCreate, P, [P, C.c_uint32]),
    (iokit.IOHIDManagerSetDeviceMatching, None, [P, P]),
    (iokit.IOHIDManagerCopyDevices, P, [P]),
    (iokit.IOHIDDeviceGetProperty, P, [P, P]),
    (iokit.IOHIDDeviceOpen, C.c_int32, [P, C.c_uint32]),
    (iokit.IOHIDDeviceClose, C.c_int32, [P, C.c_uint32]),
    (iokit.IOHIDDeviceSetReport, C.c_int32, [P, C.c_uint32, C.c_long, C.c_char_p, C.c_long]),
    (iokit.IOHIDCheckAccess, C.c_uint32, [C.c_uint32]),
]:
    fn.restype, fn.argtypes = res, args


def cfstr(s):
    return cf.CFStringCreateWithCString(None, s, 0x08000100)


def cfnum(v):
    n = C.c_int32(v)
    return cf.CFNumberCreate(None, 3, C.byref(n))


def prop(dev, name):
    ref = iokit.IOHIDDeviceGetProperty(dev, cfstr(name))
    out = C.c_int32(0)
    if ref:
        cf.CFNumberGetValue(ref, 3, C.byref(out))
    return out.value


def find_config_interface():
    match = cf.CFDictionaryCreateMutable(None, 0, C.addressof(P.in_dll(cf, "kCFTypeDictionaryKeyCallBacks")),
                                         C.addressof(P.in_dll(cf, "kCFTypeDictionaryValueCallBacks")))
    cf.CFDictionarySetValue(match, cfstr(b"VendorID"), cfnum(VID))
    cf.CFDictionarySetValue(match, cfstr(b"ProductID"), cfnum(PID))
    mgr = iokit.IOHIDManagerCreate(None, 0)
    iokit.IOHIDManagerSetDeviceMatching(mgr, match)
    devices = iokit.IOHIDManagerCopyDevices(mgr)
    count = cf.CFSetGetCount(devices) if devices else 0
    values = (P * count)()
    if count:
        cf.CFSetGetValues(devices, values)
    # Interface 1 is the only one with 8-byte output and feature reports; interface 0 has a 1-byte output.
    hits = [d for d in values if prop(d, b"MaxOutputReportSize") == 8 and prop(d, b"MaxFeatureReportSize") == 8]
    return hits, mgr, devices  # keep mgr and devices referenced while the handles are in use


def main():
    args = sys.argv[1:]
    send = "--send" in args
    hexes = [a for a in args if a != "--send"]
    if len(hexes) > 1:
        sys.exit("usage: brightness_test.py [--send] [8-byte lighting packet in hex]")
    try:
        packet = bytes.fromhex(hexes[0] if hexes else DEFAULT_PACKET)
    except ValueError:
        sys.exit("Stopped: packet is not valid hex.")
    if not is_lighting_packet(packet):
        sys.exit("Stopped: not a valid lighting packet.")
    print("Packet:", packet.hex(" ").upper())
    access = {0: "granted", 1: "denied", 2: "not decided"}.get(iokit.IOHIDCheckAccess(1), "unknown")
    print("Input Monitoring:", access)
    hits, _mgr, _devices = find_config_interface()
    print("Config interfaces found:", len(hits))
    if len(hits) != 1:
        sys.exit("Stopped: expected exactly one config interface.")
    dev = hits[0]
    rc = iokit.IOHIDDeviceOpen(dev, 0)  # 0 = shared, so typing keeps working
    print(f"Shared open: {rc & 0xFFFFFFFF:#010x}", "(OK)" if rc == 0 else "(FAILED)")
    if rc != 0:
        sys.exit(1)
    try:
        if not send:
            print("Dry run: nothing sent.")
            return
        rc = iokit.IOHIDDeviceSetReport(dev, OUTPUT_REPORT, packet[0], packet, len(packet))
        print(f"SetReport: {rc & 0xFFFFFFFF:#010x}", "(OK)" if rc == 0 else "(FAILED)")
        if rc != 0:
            sys.exit(1)
    finally:
        iokit.IOHIDDeviceClose(dev, 0)


if __name__ == "__main__":
    main()
