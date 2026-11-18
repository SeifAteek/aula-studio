"""Command-line interface for the AULA F2058."""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from . import device, protocol, remap

STATE_PATH = Path.home() / ".config" / "aula" / "state.json"
DEFAULT_LIGHTING = {"effect": protocol.EFFECTS["key-ripple"], "brightness": 2, "speed": 1, "color_option": 0}


def validated(data):
    """Check state or profile JSON and return it in canonical form."""
    if not isinstance(data, dict) or set(data) != {"lighting", "remaps"}:
        raise ValueError('profile must contain exactly "lighting" and "remaps"')
    lighting, remaps = data["lighting"], data["remaps"]
    if not isinstance(lighting, dict) or set(lighting) != set(DEFAULT_LIGHTING):
        raise ValueError(f'"lighting" must contain exactly: {", ".join(DEFAULT_LIGHTING)}')
    protocol.lighting_packet(**lighting)
    if not isinstance(remaps, dict) or not all(isinstance(v, str) for v in remaps.values()):
        raise ValueError('"remaps" must map key names to key names')
    return {"lighting": dict(lighting),
            "remaps": {remap.key_name(src): remap.key_name(dst) for src, dst in remaps.items()}}


def load_state():
    if not STATE_PATH.exists():
        return {"lighting": dict(DEFAULT_LIGHTING), "remaps": {}}
    return validated(json.loads(STATE_PATH.read_text()))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(temp, path)


def send_packet(packet, dry_run):
    print("Packet:", packet.hex(" ").upper())
    if dry_run:
        print("Dry run: nothing sent.")
        return False
    device.send(packet)
    print("Sent.")
    return True


def apply_remaps(mappings, dry_run):
    print("Key mapping:", remap.payload(mappings))
    if dry_run:
        print("Dry run: nothing applied.")
        return False
    remap.apply(mappings)
    print("Applied until this keyboard reconnects or the Mac restarts.")
    return True


def cmd_lighting(args):
    state = load_state()
    slot = None if args.slot is None else int(args.slot[1]) - 1
    updates = {"brightness": args.brightness, "speed": args.speed, "color_option": slot}
    if args.mode is not None:
        updates["effect"] = protocol.parse_effect(args.mode)
    updates = {key: value for key, value in updates.items() if value is not None}
    if not updates:
        raise ValueError("give at least one of --mode, --brightness, --speed or --slot")
    state["lighting"].update(updates)
    if send_packet(protocol.lighting_packet(**state["lighting"]), args.dry_run):
        write_json(STATE_PATH, state)


def cmd_color(_args):
    raise ValueError("the F2058 can't set RGB colors because each key has one fixed LED color.")


def cmd_remap(args):
    state = load_state()
    if args.list:
        for src, dst in sorted(state["remaps"].items()):
            print(f"{src} -> {dst}")
        return
    if (args.clear and (args.source or args.target)) or (not args.clear and not (args.source and args.target)):
        raise ValueError("use `aula remap FROM TO`, `aula remap --list` or `aula remap --clear`")
    state["remaps"] = {} if args.clear else {**state["remaps"], remap.key_name(args.source): remap.key_name(args.target)}
    if apply_remaps(state["remaps"], args.dry_run):
        write_json(STATE_PATH, state)


def cmd_macro(_args):
    raise ValueError("the F2058 cannot store macros. They need software running on the Mac, such as Karabiner-Elements.")


def cmd_save(_args):
    print("Nothing to do: the keyboard saves lighting changes automatically.")


def cmd_reset(args):
    if not args.dry_run and not args.yes:
        print("This restores all keyboard settings to factory defaults.")
        if input("Type RESET to continue: ") != "RESET":
            print("Cancelled.")
            return
    if send_packet(protocol.RESET_PACKET, args.dry_run):
        state = load_state()
        state["lighting"] = dict(DEFAULT_LIGHTING)
        write_json(STATE_PATH, state)


def cmd_profile(args):
    path = Path(args.path).expanduser()
    if args.action == "save":
        write_json(path, load_state())
        print(f"Saved profile to {path}")
        return
    state = validated(json.loads(path.read_text()))
    sent = send_packet(protocol.lighting_packet(**state["lighting"]), args.dry_run)
    applied = apply_remaps(state["remaps"], args.dry_run)
    if sent and applied:
        write_json(STATE_PATH, state)


def build_parser():
    parser = argparse.ArgumentParser(prog="aula", description="Configure an AULA Wind F2058 keyboard.")
    parser.add_argument("--dry-run", action="store_true", help="show what would happen without changing anything")
    commands = parser.add_subparsers(dest="command", required=True)

    lighting = commands.add_parser("lighting", help="set effect, brightness and speed")
    lighting.add_argument("--mode", help=f"effect name or 0-19: {', '.join(protocol.EFFECTS)}")
    lighting.add_argument("--brightness", type=int, help="0 to 13")
    lighting.add_argument("--speed", type=int, help="0 to 2")
    lighting.add_argument("--slot", type=str.upper, choices=["M1", "M2", "M3"], help="key group for gaming-keys")
    lighting.set_defaults(run=cmd_lighting)

    color = commands.add_parser("color", help="not supported by this keyboard")
    color.add_argument("--rgb")
    color.set_defaults(run=cmd_color)

    remapping = commands.add_parser("remap", help="remap a key on this Mac")
    remapping.add_argument("source", nargs="?")
    remapping.add_argument("target", nargs="?")
    remapping.add_argument("--list", action="store_true", help="show saved remaps")
    remapping.add_argument("--clear", action="store_true", help="remove all remaps")
    remapping.set_defaults(run=cmd_remap)

    macro = commands.add_parser("macro", help="not supported by this keyboard")
    macro.add_argument("slot", nargs="?")
    macro.add_argument("text", nargs="?")
    macro.set_defaults(run=cmd_macro)

    commands.add_parser("save", help="explain how settings are saved").set_defaults(run=cmd_save)

    reset = commands.add_parser("reset", help="restore factory defaults")
    reset.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    reset.set_defaults(run=cmd_reset)

    profile = commands.add_parser("profile", help="save or load a JSON profile")
    profile.add_argument("action", choices=["save", "load"])
    profile.add_argument("path")
    profile.set_defaults(run=cmd_profile)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        args.run(args)
    except subprocess.CalledProcessError as error:
        print(f"aula: hidutil failed: {(error.stderr or '').strip() or error}", file=sys.stderr)
        return 1
    except (ValueError, TypeError, OSError, EOFError, device.DeviceError) as error:
        print(f"aula: {error}", file=sys.stderr)
        return 1
    return 0
