#!/usr/bin/env python3
"""Phase 1: read-only identification. Sends no reports to the keyboard."""
import plistlib
import subprocess
from collections import defaultdict

VID, PID = 0x1A2C, 0x9EF4
KINDS = {0x80: "input", 0x90: "output", 0xB0: "feature"}


def parse_descriptor(data):
    """Return {(kind, report_id): {"bits": n, "pages": set}} and top-level collections."""
    glob = dict(page=0, size=0, count=0, rid=0)
    stack, reports, tops = [], defaultdict(lambda: {"bits": 0, "pages": set()}), []
    usages, depth, i = [], 0, 0
    while i < len(data):
        head = data[i]
        if head == 0xFE:  # long item: skip
            i += 3 + data[i + 1]
            continue
        n = {0: 0, 1: 1, 2: 2, 3: 4}[head & 3]
        val = int.from_bytes(data[i + 1 : i + 1 + n], "little")
        i += 1 + n
        tag = head & 0xFC
        if tag == 0x04: glob["page"] = val
        elif tag == 0x74: glob["size"] = val
        elif tag == 0x94: glob["count"] = val
        elif tag == 0x84: glob["rid"] = val
        elif tag == 0xA4: stack.append(dict(glob))
        elif tag == 0xB4: glob = stack.pop()
        elif tag == 0x08: usages.append(val)
        elif tag == 0xA0:
            if depth == 0:
                tops.append((glob["page"], usages[0] if usages else 0))
            depth += 1
            usages = []
        elif tag == 0xC0: depth -= 1
        elif tag in KINDS:
            r = reports[(KINDS[tag], glob["rid"])]
            r["bits"] += glob["size"] * glob["count"]
            r["pages"].add(glob["page"])
            usages = []
    return dict(reports), tops


# Self-check: vendor page 0xFF00, report ID 6, 64-byte feature report.
_r, _t = parse_descriptor(bytes.fromhex("0600FF0901A10185067508953F0902B102C0"))
assert _t == [(0xFF00, 1)] and _r[("feature", 6)]["bits"] == 63 * 8


def walk(node):
    if isinstance(node, dict):
        yield node
        for child in node.get("IORegistryEntryChildren", []):
            yield from walk(child)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def main():
    raw = subprocess.run(["ioreg", "-a", "-l", "-r", "-c", "IOUSBHostDevice"],
                         capture_output=True, check=True).stdout
    nodes = [n for n in walk(plistlib.loads(raw))]
    seen = set()
    for n in nodes:
        if n.get("idVendor") == VID and n.get("idProduct") == PID and "bDeviceClass" in n:
            print(f"Device: speed={n.get('Device Speed')} bcdDevice={n.get('bcdDevice'):#06x} "
                  f"bMaxPacketSize0={n.get('bMaxPacketSize0')} configs={n.get('bNumConfigurations')}")
        if "bInterfaceNumber" in n and n.get("idVendor") == VID and n.get("idProduct") == PID:
            print(f"USB interface {n['bInterfaceNumber']}: class={n.get('bInterfaceClass')} "
                  f"subclass={n.get('bInterfaceSubClass')} protocol={n.get('bInterfaceProtocol')}")
    for n in nodes:
        desc = n.get("ReportDescriptor")
        if not desc or n.get("VendorID") != VID or n.get("ProductID") != PID or bytes(desc) in seen:
            continue
        seen.add(bytes(desc))
        reports, tops = parse_descriptor(bytes(desc))
        print(f"\nInterface location={n.get('LocationID'):#x} descriptor={len(desc)} bytes "
              f"maxIn={n.get('MaxInputReportSize')} maxOut={n.get('MaxOutputReportSize')} "
              f"maxFeature={n.get('MaxFeatureReportSize')}")
        print("  top-level:", ", ".join(f"page {p:#06x} usage {u:#04x}" for p, u in tops))
        for (kind, rid), r in sorted(reports.items()):
            pages = ",".join(f"{p:#06x}" for p in sorted(r["pages"]))
            print(f"  {kind:8} id={rid:#04x} payload={r['bits'] / 8:g} bytes pages={pages}")
        print("  raw:", bytes(desc).hex())

    import hid
    print("\nOpen test (open and close only, no data transferred):")
    for d in hid.enumerate(VID, PID):
        label = f"if{d['interface_number']} page {d['usage_page']:#06x} usage {d['usage']:#04x}"
        dev = hid.device()
        try:
            dev.open_path(d["path"])
            print(f"  {label}: OK")
        except OSError as e:
            print(f"  {label}: BLOCKED ({e})")
        finally:
            dev.close()


if __name__ == "__main__":
    main()
