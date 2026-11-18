"""Offline tests. The device and hidutil are replaced, so nothing reaches the keyboard."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from aula import cli, device, protocol, remap


class ProtocolTests(unittest.TestCase):
    def test_hardware_confirmed_packets(self):
        self.assertEqual(protocol.lighting_packet(0x0B, 2, 1).hex(), "07ffff0b02010000")
        self.assertEqual(protocol.lighting_packet(0x02, 2, 2).hex(), "07ffff0202020000")

    def test_rejects_out_of_range_values(self):
        for args in [(20, 2, 1), (0, 14, 1), (0, 2, 3), (0, 2, 1, 3), (True, 2, 1), ("1", 2, 1)]:
            with self.assertRaises(ValueError):
                protocol.lighting_packet(*args)

    def test_allowlist(self):
        self.assertTrue(protocol.is_allowed(protocol.RESET_PACKET))
        self.assertTrue(protocol.is_allowed(protocol.lighting_packet(0x13, 13, 2, 2)))
        self.assertFalse(protocol.is_allowed(bytes.fromhex("07FFFF0B0E010000")))
        for packet in ["07F1000000000000", "07FFFF2000000700", "07FFFF1402000000", "07FFFF0B0201", "07F0AA0000000001"]:
            self.assertFalse(protocol.is_allowed(bytes.fromhex(packet)), packet)

    def test_device_blocks_unlisted_packet_before_touching_usb(self):
        with mock.patch.object(device, "_config_interface") as find:
            with self.assertRaises(device.DeviceError):
                device.send(bytes.fromhex("07F1000000000000"))
        find.assert_not_called()

    def test_parse_effect(self):
        self.assertEqual(protocol.parse_effect("WAVE"), 4)
        self.assertEqual(protocol.parse_effect("0x13"), 19)
        with self.assertRaises(ValueError):
            protocol.parse_effect("20")


class RemapTests(unittest.TestCase):
    def test_capslock_to_escape_payload(self):
        mapping = json.loads(remap.payload({"CAPSLOCK": "ESC"}))["UserKeyMapping"][0]
        self.assertEqual(mapping["HIDKeyboardModifierMappingSrc"], 0x700000039)
        self.assertEqual(mapping["HIDKeyboardModifierMappingDst"], 0x700000029)

    def test_digits_and_aliases(self):
        self.assertEqual(remap.KEYS["1"], 0x1E)
        self.assertEqual(remap.KEYS["0"], 0x27)
        self.assertEqual(remap.key_name("caps"), "CAPSLOCK")


class CliTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)
        for patcher in [mock.patch.object(cli, "STATE_PATH", self.folder / "state.json"),
                        mock.patch.object(cli.device, "send"), mock.patch.object(cli.remap, "apply")]:
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_cli(self, *argv):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cli.main(list(argv))

    def test_partial_update_keeps_other_lighting_values(self):
        self.assertEqual(self.run_cli("lighting", "--mode", "wave", "--speed", "2"), 0)
        self.assertEqual(self.run_cli("lighting", "--brightness", "4"), 0)
        cli.device.send.assert_called_with(bytes.fromhex("07FFFF0404020000"))

    def test_slot_selects_gaming_key_group(self):
        self.assertEqual(self.run_cli("lighting", "--mode", "gaming-keys", "--slot", "m3"), 0)
        cli.device.send.assert_called_with(bytes.fromhex("07FFFF0102010200"))

    def test_dry_run_sends_and_saves_nothing(self):
        self.assertEqual(self.run_cli("--dry-run", "lighting", "--brightness", "4"), 0)
        cli.device.send.assert_not_called()
        self.assertFalse(cli.STATE_PATH.exists())

    def test_failed_send_does_not_save_state(self):
        cli.device.send.side_effect = device.DeviceError("unplugged")
        self.assertEqual(self.run_cli("lighting", "--brightness", "4"), 1)
        self.assertFalse(cli.STATE_PATH.exists())

    def test_reset_needs_exact_confirmation(self):
        with mock.patch("builtins.input", return_value="yes"):
            self.assertEqual(self.run_cli("reset"), 0)
        cli.device.send.assert_not_called()
        with mock.patch("builtins.input", return_value="RESET"):
            self.assertEqual(self.run_cli("reset"), 0)
        cli.device.send.assert_called_once_with(protocol.RESET_PACKET)

    def test_remaps_accumulate_and_clear(self):
        self.run_cli("remap", "caps", "esc")
        self.run_cli("remap", "F1", "F2")
        cli.remap.apply.assert_called_with({"CAPSLOCK": "ESC", "F1": "F2"})
        self.run_cli("remap", "--clear")
        cli.remap.apply.assert_called_with({})

    def test_profile_round_trip(self):
        path = self.folder / "desk.json"
        self.run_cli("lighting", "--mode", "key-ripple", "--brightness", "3")
        self.run_cli("remap", "caps", "esc")
        self.assertEqual(self.run_cli("profile", "save", str(path)), 0)
        cli.device.send.reset_mock()
        self.assertEqual(self.run_cli("profile", "load", str(path)), 0)
        cli.device.send.assert_called_once_with(bytes.fromhex("07FFFF0B03010000"))
        cli.remap.apply.assert_called_with({"CAPSLOCK": "ESC"})

    def test_bad_profiles_are_rejected_without_sending(self):
        lighting = {"effect": 99, "brightness": 2, "speed": 1, "color_option": 0}
        for data in [[], {"lighting": lighting, "remaps": {}}, {"lighting": {**lighting, "effect": 1, "x": 1}, "remaps": {}},
                     {"lighting": {**lighting, "effect": 1}, "remaps": {"CAPS": "NOPE"}}]:
            path = self.folder / "bad.json"
            path.write_text(json.dumps(data))
            self.assertEqual(self.run_cli("profile", "load", str(path)), 1)
        cli.device.send.assert_not_called()

    def test_unsupported_features_fail_clearly(self):
        self.assertEqual(self.run_cli("color", "--rgb", "ff0000"), 1)
        self.assertEqual(self.run_cli("macro", "M1", "hello"), 1)
        cli.device.send.assert_not_called()


if __name__ == "__main__":
    unittest.main()
