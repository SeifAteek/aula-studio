#!/usr/bin/env python3
"""Show all 22 lighting effects for filming. Use --dry-run to list them without sending."""
import sys
import time

from aula import cli, device, protocol

SECONDS = 10
BRIGHTNESS = protocol.MAX_BRIGHTNESS
SPEED = 1
REACTIVE = {0x03, 0x08, 0x09, 0x0A, 0x0B}  # These only show their motion while keys are pressed.


def sequence():
    steps = []
    for name, effect in sorted(protocol.EFFECTS.items(), key=lambda item: item[1]):
        slots = range(3) if effect == protocol.EFFECTS["gaming-keys"] else [0]
        for slot in slots:
            label = f"{name} M{slot + 1}" if len(slots) == 3 else name
            steps.append((label, effect, slot))
    return steps


assert len(sequence()) == 22 and sequence()[1:4] == [("gaming-keys M1", 1, 0), ("gaming-keys M2", 1, 1), ("gaming-keys M3", 1, 2)]


def main():
    dry_run = sys.argv[1:] == ["--dry-run"]
    if sys.argv[1:] and not dry_run:
        sys.exit("usage: effect_video.py [--dry-run]")
    steps = sequence()
    if not dry_run:
        print("Start filming now. The first effect begins in 5 seconds.", flush=True)
        time.sleep(5)
    for number, (label, effect, slot) in enumerate(steps, 1):
        packet = protocol.lighting_packet(effect, BRIGHTNESS, SPEED, slot)
        action = "  TYPE NOW" if effect in REACTIVE else ""
        print(f"[{number:2}/{len(steps)}] {effect:02X} {label:<16} {packet.hex(' ').upper()}{action}", flush=True)
        if not dry_run:
            device.send(packet)
            time.sleep(SECONDS)
    final = {"effect": protocol.EFFECTS["always-on"], "brightness": BRIGHTNESS, "speed": SPEED, "color_option": 0}
    print("Finished: always-on, every key lit, ready for the photo.", flush=True)
    if not dry_run:
        device.send(protocol.lighting_packet(**final))
        state = cli.load_state()
        state["lighting"] = final
        cli.write_json(cli.STATE_PATH, state)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("Stopped.")
    except device.DeviceError as error:
        sys.exit(f"Stopped: {error}")
