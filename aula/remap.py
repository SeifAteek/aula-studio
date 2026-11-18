"""Key remapping through macOS hidutil, because the F2058 has no onboard remap command."""
import json
import string
import subprocess

from . import protocol

KEYS = {letter: 0x04 + i for i, letter in enumerate(string.ascii_uppercase)}
KEYS.update({str((i + 1) % 10): 0x1E + i for i in range(10)})
KEYS.update({f"F{i + 1}": 0x3A + i for i in range(12)})
KEYS.update({
    "ENTER": 0x28, "ESC": 0x29, "BACKSPACE": 0x2A, "TAB": 0x2B, "SPACE": 0x2C, "MINUS": 0x2D,
    "EQUAL": 0x2E, "LBRACKET": 0x2F, "RBRACKET": 0x30, "BACKSLASH": 0x31, "SEMICOLON": 0x33,
    "QUOTE": 0x34, "GRAVE": 0x35, "COMMA": 0x36, "PERIOD": 0x37, "SLASH": 0x38, "CAPSLOCK": 0x39,
    "PRINTSCREEN": 0x46, "SCROLLLOCK": 0x47, "PAUSE": 0x48, "INSERT": 0x49, "HOME": 0x4A,
    "PAGEUP": 0x4B, "DELETE": 0x4C, "END": 0x4D, "PAGEDOWN": 0x4E, "RIGHT": 0x4F, "LEFT": 0x50,
    "DOWN": 0x51, "UP": 0x52, "LCTRL": 0xE0, "LSHIFT": 0xE1, "LALT": 0xE2, "LCMD": 0xE3,
    "RCTRL": 0xE4, "RSHIFT": 0xE5, "RALT": 0xE6, "RCMD": 0xE7,
})
ALIASES = {"ESCAPE": "ESC", "CAPS": "CAPSLOCK", "RETURN": "ENTER", "CMD": "LCMD", "WIN": "LCMD",
           "CTRL": "LCTRL", "SHIFT": "LSHIFT", "ALT": "LALT", "OPTION": "LALT"}


def key_name(text):
    name = text.strip().upper()
    name = ALIASES.get(name, name)
    if name not in KEYS:
        raise ValueError(f"unknown key {text!r}")
    return name


def payload(mappings):
    return json.dumps({"UserKeyMapping": [
        {"HIDKeyboardModifierMappingSrc": 0x700000000 | KEYS[src],
         "HIDKeyboardModifierMappingDst": 0x700000000 | KEYS[dst]}
        for src, dst in sorted(mappings.items())
    ]})


def apply(mappings):
    match = json.dumps({"VendorID": protocol.VENDOR_ID, "ProductID": protocol.PRODUCT_ID})
    subprocess.run(["hidutil", "property", "--matching", match, "--set", payload(mappings)],
                   check=True, capture_output=True, text=True)
