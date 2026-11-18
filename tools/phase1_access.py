#!/usr/bin/env python3
"""Phase 1: diagnose HID access. Opens and closes only; transfers no reports."""
import ctypes as C
import ctypes.util

iokit = C.CDLL(ctypes.util.find_library("IOKit"))
cf = C.CDLL(ctypes.util.find_library("CoreFoundation"))
P = C.c_void_p
for fn, res, args in [
    (cf.CFStringCreateWithCString, P, [P, C.c_char_p, C.c_uint32]),
    (cf.CFNumberCreate, P, [P, C.c_long, P]),
    (cf.CFDictionaryCreateMutable, P, [P, C.c_long, P, P]),
    (cf.CFDictionarySetValue, None, [P, P, P]),
    (cf.CFSetGetCount, C.c_long, [P]),
    (cf.CFSetGetValues, None, [P, P]),
    (iokit.IOHIDManagerCreate, P, [P, C.c_uint32]),
    (iokit.IOHIDManagerSetDeviceMatching, None, [P, P]),
    (iokit.IOHIDManagerCopyDevices, P, [P]),
    (iokit.IOHIDDeviceOpen, C.c_int32, [P, C.c_uint32]),
    (iokit.IOHIDDeviceClose, C.c_int32, [P, C.c_uint32]),
    (iokit.IOHIDCheckAccess, C.c_uint32, [C.c_uint32]),
]:
    fn.restype, fn.argtypes = res, args

ACCESS = {0: "granted", 1: "denied", 2: "not decided yet"}
print("Input Monitoring for this process:", ACCESS.get(iokit.IOHIDCheckAccess(1), "unknown"))


def key(s):
    return cf.CFStringCreateWithCString(None, s, 0x08000100)


def num(v):
    n = C.c_int32(v)
    return cf.CFNumberCreate(None, 3, C.byref(n))


match = cf.CFDictionaryCreateMutable(None, 0, C.addressof(C.c_void_p.in_dll(cf, "kCFTypeDictionaryKeyCallBacks")),
                                     C.addressof(C.c_void_p.in_dll(cf, "kCFTypeDictionaryValueCallBacks")))
for k, v in [(b"VendorID", 0x1A2C), (b"ProductID", 0x9EF4)]:  # interface 1's primary page is 0x000C, not 0xFF01
    cf.CFDictionarySetValue(match, key(k), num(v))

mgr = iokit.IOHIDManagerCreate(None, 0)
iokit.IOHIDManagerSetDeviceMatching(mgr, match)
devices = iokit.IOHIDManagerCopyDevices(mgr)
count = cf.CFSetGetCount(devices) if devices else 0
print("Matching HID interfaces:", count)
if count:
    values = (P * count)()
    cf.CFSetGetValues(devices, values)
    for dev in values:
        rc = iokit.IOHIDDeviceOpen(dev, 0)  # 0 = shared; the keyboard keeps typing
        print(f"Shared open: IOReturn {rc & 0xFFFFFFFF:#010x}", "(OK)" if rc == 0 else "")
        if rc == 0:
            iokit.IOHIDDeviceClose(dev, 0)
