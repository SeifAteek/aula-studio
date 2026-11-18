"""F2058 packet format. No device I/O lives here; see PROTOCOL.md for the evidence."""

VENDOR_ID = 0x1A2C
PRODUCT_ID = 0x9EF4
REPORT_ID = 0x07
PACKET_SIZE = 8

MAX_BRIGHTNESS = 13  # Matches the driver's slider and the 13 steps on the keyboard's knob.
MAX_SPEED = 2
MAX_COLOR_OPTION = 2

# Names follow the driver's effect list, except gaming-keys, key-wave and zigzag, which describe observed behavior.
EFFECTS = {
    "always-on": 0x00,
    "gaming-keys": 0x01,
    "breathing": 0x02,
    "off-on-press": 0x03,
    "wave": 0x04,
    "water-ripple": 0x05,
    "flowing": 0x06,
    "streamer": 0x07,
    "key-wave": 0x08,
    "trigger": 0x09,
    "snow": 0x0A,
    "key-ripple": 0x0B,
    "snake": 0x0C,
    "blossom": 0x0D,
    "storm": 0x0E,
    "zigzag": 0x0F,
    "stars": 0x10,
    "stream": 0x11,
    "diagonal": 0x12,
    "sine": 0x13,
}

RESET_PACKET = bytes.fromhex("07F0AA0000000000")


def parse_effect(text):
    """Accept an effect name, a decimal number, or a 0x-prefixed number."""
    name = text.strip().lower()
    if name in EFFECTS:
        return EFFECTS[name]
    try:
        value = int(name, 0)
    except ValueError:
        raise ValueError(f"unknown effect {text!r}. Choose from: {', '.join(EFFECTS)}") from None
    if value not in EFFECTS.values():
        raise ValueError(f"effect must be 0 to {max(EFFECTS.values())}")
    return value


def _check(label, value, maximum):
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= maximum:
        raise ValueError(f"{label} must be a whole number from 0 to {maximum}")


def lighting_packet(effect, brightness, speed, color_option=0):
    _check("effect", effect, max(EFFECTS.values()))
    _check("brightness", brightness, MAX_BRIGHTNESS)
    _check("speed", speed, MAX_SPEED)
    _check("color option", color_option, MAX_COLOR_OPTION)
    return bytes([REPORT_ID, 0xFF, 0xFF, effect, brightness, speed, color_option, 0x00])


def is_allowed(packet):
    """Allowlist: anything else, including firmware or bootloader traffic, must never be sent."""
    if packet == RESET_PACKET:
        return True
    return (len(packet) == PACKET_SIZE and packet[:3] == bytes([REPORT_ID, 0xFF, 0xFF])
            and packet[3] <= max(EFFECTS.values()) and packet[4] <= MAX_BRIGHTNESS
            and packet[5] <= MAX_SPEED and packet[6] <= MAX_COLOR_OPTION and packet[7] == 0)
