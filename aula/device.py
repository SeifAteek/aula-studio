"""Send reports through IOKit. A shared open keeps the keyboard typing while the tool runs."""
import ctypes as C
import ctypes.util

from . import protocol

OUTPUT_REPORT = 1  # kIOHIDReportTypeOutput
NOT_PERMITTED = 0xE00002E2


class DeviceError(Exception):
    pass


_iokit = C.CDLL(ctypes.util.find_library("IOKit"))
_cf = C.CDLL(ctypes.util.find_library("CoreFoundation"))
_P = C.c_void_p
for _fn, _res, _args in [
    (_cf.CFStringCreateWithCString, _P, [_P, C.c_char_p, C.c_uint32]),
    (_cf.CFNumberCreate, _P, [_P, C.c_long, _P]),
    (_cf.CFNumberGetValue, C.c_bool, [_P, C.c_long, _P]),
    (_cf.CFDictionaryCreateMutable, _P, [_P, C.c_long, _P, _P]),
    (_cf.CFDictionarySetValue, None, [_P, _P, _P]),
    (_cf.CFSetGetCount, C.c_long, [_P]),
    (_cf.CFSetGetValues, None, [_P, _P]),
    (_iokit.IOHIDManagerCreate, _P, [_P, C.c_uint32]),
    (_iokit.IOHIDManagerSetDeviceMatching, None, [_P, _P]),
    (_iokit.IOHIDManagerCopyDevices, _P, [_P]),
    (_iokit.IOHIDDeviceGetProperty, _P, [_P, _P]),
    (_iokit.IOHIDDeviceOpen, C.c_int32, [_P, C.c_uint32]),
    (_iokit.IOHIDDeviceClose, C.c_int32, [_P, C.c_uint32]),
    (_iokit.IOHIDDeviceSetReport, C.c_int32, [_P, C.c_uint32, C.c_long, C.c_char_p, C.c_long]),
]:
    _fn.restype, _fn.argtypes = _res, _args


def _cfstr(text):
    return _cf.CFStringCreateWithCString(None, text, 0x08000100)


def _cfnum(value):
    number = C.c_int32(value)
    return _cf.CFNumberCreate(None, 3, C.byref(number))


def _prop(dev, name):
    ref = _iokit.IOHIDDeviceGetProperty(dev, _cfstr(name))
    out = C.c_int32(0)
    if ref:
        _cf.CFNumberGetValue(ref, 3, C.byref(out))
    return out.value


def _config_interface():
    match = _cf.CFDictionaryCreateMutable(None, 0, C.addressof(_P.in_dll(_cf, "kCFTypeDictionaryKeyCallBacks")),
                                          C.addressof(_P.in_dll(_cf, "kCFTypeDictionaryValueCallBacks")))
    _cf.CFDictionarySetValue(match, _cfstr(b"VendorID"), _cfnum(protocol.VENDOR_ID))
    _cf.CFDictionarySetValue(match, _cfstr(b"ProductID"), _cfnum(protocol.PRODUCT_ID))
    manager = _iokit.IOHIDManagerCreate(None, 0)
    _iokit.IOHIDManagerSetDeviceMatching(manager, match)
    devices = _iokit.IOHIDManagerCopyDevices(manager)
    count = _cf.CFSetGetCount(devices) if devices else 0
    if not count:
        raise DeviceError("AULA F2058 not found. Check that the keyboard is plugged in.")
    values = (_P * count)()
    _cf.CFSetGetValues(devices, values)
    # Interface 1 is the only one with 8-byte output and feature reports.
    hits = [d for d in values if _prop(d, b"MaxOutputReportSize") == protocol.PACKET_SIZE
            and _prop(d, b"MaxFeatureReportSize") == protocol.PACKET_SIZE]
    if len(hits) != 1:
        raise DeviceError(f"Expected one configuration interface, found {len(hits)}.")
    return hits[0], manager, devices  # The caller keeps these references alive during the transfer.


def send(packet):
    if not protocol.is_allowed(packet):
        raise DeviceError(f"Blocked unrecognized packet: {packet.hex(' ').upper()}")
    dev, _manager, _devices = _config_interface()
    rc = _iokit.IOHIDDeviceOpen(dev, 0) & 0xFFFFFFFF
    if rc == NOT_PERMITTED:
        raise DeviceError("macOS denied access. Allow this app under System Settings > Privacy & "
                          "Security > Input Monitoring, then reopen it.")
    if rc:
        raise DeviceError(f"Could not open the keyboard (IOReturn {rc:#010x}).")
    try:
        rc = _iokit.IOHIDDeviceSetReport(dev, OUTPUT_REPORT, packet[0], packet, len(packet)) & 0xFFFFFFFF
    finally:
        _iokit.IOHIDDeviceClose(dev, 0)
    if rc:
        raise DeviceError(f"The keyboard rejected the packet (IOReturn {rc:#010x}).")
