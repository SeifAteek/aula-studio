# AULA Wind F2058 USB HID protocol log

Status: **one lighting packet confirmed on the F2058 (2026-11-18). Everything else is untested.**

## Device (observed on macOS 27.2, Apple M3)

| Field | Value |
|---|---|
| Vendor ID / Product ID | `0x1A2C` / `0x9EF4` |
| Manufacturer / product strings | `SEMICO` / `USB Gaming Keyboard` |
| Device release | `0x0110` |
| USB speed | Low speed, 1.5 Mb/s |
| Control endpoint packet size | 8 bytes |

## HID reports

Payload sizes exclude the report ID byte.

| USB interface | Report ID | Type | Payload | Usage page | Purpose |
|---|---|---|---|---|---|
| 0 | none | Input | 8 bytes | `0x0007` | Boot keyboard |
| 0 | none | Output | 1 byte | `0x0008` | Keyboard LEDs |
| 1 | `0x01` | Input | 2 bytes | `0x000C` | Media keys |
| 1 | `0x02` | Input | 1 byte | `0x0001` | System control |
| 1 | `0x03` | Input | 1 byte | `0xFF00` | Vendor input, purpose unknown |
| 1 | `0x04`, `0x05`, `0x06` | Input | 7 bytes each | `0x0007` | Extended key state |
| 1 | `0x07` | Feature | 7 bytes | `0xFF01` | **Likely configuration channel (unconfirmed)** |
| 1 | `0x07` | Output | 7 bytes | `0xFF01` | **Likely configuration channel (unconfirmed)** |

## Access

Opening the device without Input Monitoring returns `0xE00002E2` (`kIOReturnNotPermitted`).
A shared open (`IOHIDDeviceOpen` with options `0`) works when run from the Claude app's Terminal panel with Input Monitoring granted to Claude.

## Factory reset

The official F2058 driver's Restore button sends `07 F0 AA 00 00 00 00 00` as output report 7, after warning "All settings will be restored". Found by static analysis and **not yet tested on this keyboard**.
Other AULA models also document holding Fn+Esc for about 3 to 5 seconds. That shortcut is unconfirmed on the F2058.

## Manufacturer product page

Details from the product image supplied by the owner on 2026-11-18:

- **Lighting:** 22 lighting effects. The driver lists 20 effects, and effect `01` has three slots, which would total 22 (19 other effects + `M1`, `M2` and `M3`). This count is an inference.
- **Custom lighting:** `M1`, `M2` and `M3` are factory-set to light the gaming keys and can be customized on the keyboard. In a backlight mode, hold an M button for 3 seconds until the knob indicator flashes, press the keys to include, then short-press the same M button to confirm.
- **Speed:** the page advertises 5 speed levels, while the driver's slider has 3 (`0` to `2`). On 2026-11-18, the owner tested speed values `03` and `04` and both made the lighting static, so only `00` to `02` are valid.
- **Shortcuts:** Fn+Right raises speed and Fn+Left lowers it. The knob adjusts brightness.
- **Profiles:** the Windows software offers 3 preset configurations and a one-key factory restore.

## Official driver analysis (static only, never executed)

Source: `AULA F2058 Driver setup v1.0.5.7`, program `ShinetekTools.exe` (SHA-256 `810f3ed7f10b877250f9254911eaaff178530494d3a715785e4d4a165e67ba8f`). Its `config.xml` names `vid=1a2c pid=9ef4 interface=1 subdevice=7`.

| Function | Bytes | Windows call | Status |
|---|---|---|---|
| Set main lighting | `07 FF FF <effect> <brightness> <speed> <color option> 00` | `HidD_SetFeature`, 8 bytes | Effect, brightness and speed confirmed on hardware |
| Read firmware version | Send `07 F1 00 00 00 00 00 00`, then read feature report 7. Version = `byte1 << 8 \| byte2` | `HidD_SetFeature`, `HidD_GetFeature` | Untested |
| Restore settings | `07 F0 AA 00 00 00 00 00` | `WriteFile` | Untested |
| Set side LEDs | `07 FF FF 20 00 00 <(brightness << 4) \| mode> 00` | `HidD_SetFeature`, 8 bytes | Untested. The Side LED page is hidden in this driver's UI |

Lighting details from the driver:
- The apply routine maps stored color option `0` or `1` to byte 6 `00`, `2` to `01`, and `3` to `02`.
- A second routine copies four stored bytes unchanged into bytes 4 to 7, so the meaning of bytes 6 and 7 is not fully settled.
- The driver's interface has a "Loader" control with choices `M1`, `M2` and `M3`, and its Chinese translation of "Loader" means "custom". On effect `01`, byte 6 selects the slot: `00` is `M1`, `01` is `M2` and `02` is `M3`. Hardware showed a different key group for each, confirmed on 2026-11-18.
- The interface also has a profile list with `P1`, `P2` and `P3`. No command that uploads a custom key pattern has been found.
- Sliders allow speed `0` to `2`. Brightness is `0` to `5` on one settings page and `0` to `13` on the others. The effect-to-page mapping is unresolved.
- The keyboard's physical knob has 13 brightness steps, reported by the owner on 2026-11-18, which matches the `0` to `13` slider. Brightness `02` is therefore level 2 of 13, and the "40%" labels in this log came from the F2067 scale.
- `07 FF FF 0B 0D 01 00 00` set key ripple at full brightness, confirmed on hardware on 2026-11-18. Brightness `0D` (13) is the maximum.

Key remapping and macros: no HID command for either was found. The program's only other device channel is IOCTLs `0xB600C` to `0xB6028` sent to `kbfiltr.sys`, a Windows keyboard filter driver. This indicates remaps and macros run on the Windows PC and are not stored on the keyboard. Indirect calls could not be fully excluded.

Saving: the driver has no separate save command, which matches the persistence seen on hardware.

## Reading settings from the keyboard (tested 2026-11-18)

No way to read lighting, remaps or macros has been found.

- **Driver:** the only keyboard read in use is the firmware version. Lighting and macro settings are kept on the PC in files such as `ledeffect.xml` and `macro.xml`. The driver's general input-reading routines have no callers that static analysis could find.
- **Hardware test:** `tools/read_monitor.py` polled feature report 7 five times a second and listened for vendor input report 3 for 300 seconds while the owner changed lighting with the keyboard's shortcuts. Feature report 7 stayed `07 01 00 00 00 00 00 00`, and no vendor input report arrived.
- **Feature report 7:** the constant value fits the driver's version format, `byte1 << 8 | byte2`, as version 1.0. This is an inference.
- **Not tried:** sending guessed query commands, because commands of unknown purpose are forbidden.

## macOS key remapping (confirmed 2026-11-18)

Remaps do not use a keyboard command. `aula remap` calls `hidutil property --matching '{"VendorID":6700,"ProductID":40692}' --set ...` with `UserKeyMapping`, using key codes `0x700000000 | <HID usage>`.

`aula remap CAPSLOCK ESC` (source `0x700000039`, target `0x700000029`) made CapsLock on the F2058 act as Esc. The mapping lasts until the keyboard reconnects or the Mac restarts.

Effect names are listed under "F2058 effect map".

## Forbidden commands

Never send firmware-update, bootloader, DFU or flash-erase commands, or any command whose purpose is unknown.
The driver's Upgrade feature starts a separate updater program, and this package includes no firmware file. The tool must never implement it.

## Candidate commands (from the AULA F2067; only the packet under "Confirmed commands" is tested on the F2058)

The F2067 is `1A2C:9CF4`. These commands are documented by the
[aegis-2067usb-protocol](https://github.com/progzone122/aegis-2067usb-protocol) project.

Transport: HID SET_REPORT, `bmRequestType 0x21`, `bRequest 0x09`, `wValue 0x0207` (output report 7), 8 bytes.
The F2067 tool uses `wIndex 0`. The F2058 exposes report 7 on interface 1, so it probably needs `wIndex 1`.

Lighting packet: `07 FF FF <effect> <brightness> <speed> <mode> 00`

| Field | Values |
|---|---|
| Effect | `00` Swim, `01` Gossip/Sea, `02` Rainbow wheel, `03` Ripple diffusion, `04` Retinue scanning, `05` Crossfire, `06` Respire, `07` Blossoming, `08` Shadow follows, `09` Comet tail-tracking, `0A` Rotating windmill, `0B` Fixed on, `0C` Stars twinkle, `0D` Neon stream, `0E` Instant, `0F` Progressive scanning, `10` Collision, `11` Rotating storm, `12` Random flying, `13` Colorful waterfalls |
| Brightness | `00` 0%, `01` 20%, `02` 40%, `03` 60%, `04` 80%, `05` 100% |
| Speed | `00` slow, `01` medium, `02` fast |
| Mode ("Loader") | `00` Mode 1, `01` Mode 2 |

Settings restore: `07 F0 AA 00 00 00 00 00`. The F2058 driver uses the same bytes. **Send only with explicit approval, because it resets all settings.**

Not documented for the F2067: custom RGB color, key remapping, macros, and saving to onboard memory.

## Confirmed commands

### Set lighting: key ripple, 40% brightness (confirmed 2026-11-18)

| Field | Value |
|---|---|
| Bytes | `07 FF FF 0B 02 01 00 00` |
| Transport | `IOHIDDeviceSetReport`, output report type, report ID 7, 8 bytes including the ID |
| Target | USB interface 1 (the HID interface with 8-byte output and feature reports) |
| macOS result | `0x00000000` |
| Observed | Backlight stays lit at about 40% brightness and ripples when keys are pressed |

Confirmed by sight: effect `0B` and brightness `02`.
Persistence: the setting survived unplugging and reconnecting the keyboard, with no separate save command.
CLI: `aula lighting --mode key-ripple --brightness 2 --speed 1` sends this packet. The CLI produced the same result (confirmed 2026-11-18).
Not confirmed: speed `01` and mode `00` (a steady effect shows no speed), and other effect and brightness values.

### Set lighting: breathing (confirmed 2026-11-18)

| Field | Value |
|---|---|
| Bytes | `07 FF FF 02 02 00 00 00` |
| Transport and target | Same as above |
| macOS result | `0x00000000` |
| Observed | Backlight flashes, matching the driver's breathing effect |
| Persistence | Survived unplugging and reconnecting, with no separate save command |

### Set lighting: speed byte (confirmed 2026-11-18)

Byte 5 controls animation speed. On effect `02`, `07 FF FF 02 02 02 00 00` (speed `02`) flashed visibly faster than `07 FF FF 02 02 00 00 00` (speed `00`).

Not confirmed: speed `01` as a middle setting, and mode byte 6.

### F2058 effect map

Names come from the Chinese labels in the official F2058 driver. All 20 effects in the driver's list have been checked on hardware, and the driver's effect order held for every one. The CLI names `gaming-keys`, `key-wave` and `zigzag` describe observed behavior because their driver labels are poetic or duplicated.

The keyboard's box lists 22 lighting types, while the driver's effect list has 20 (`00` to `13`). Values `14` to `17` are outside the driver's list. The owner tested them on 2026-11-18, and none is a new effect, so the CLI does not offer them.

| Value | Hardware result |
|---|---|
| `14` | Stays lit like `00` (always on) |
| `15` | Stays lit like `00` |
| `16` | Stays lit like `00` |
| `17` | Stays lit like `00` |

| Value | CLI name | Driver label | Meaning | Hardware |
|---|---|---|---|---|
| `00` | `always-on` | 常亮 | Always on | **Confirmed**, stays on with no ripple |
| `01` | `gaming-keys` | 指点江山 | Lights the key group stored in slot `M1`, `M2` or `M3` | **Confirmed**, byte 6 selects the slot |
| `02` | `breathing` | 呼吸 | Breathing | **Confirmed**, seen as flashing |
| `03` | `off-on-press` | 随按即灭 | Off when pressed | **Confirmed**, keys turn off when pressed |
| `04` | `wave` | 随波逐流 | Wave follow | **Confirmed**, wave of light |
| `05` | `water-ripple` | 滴水涟漪 | Water ripple | **Confirmed**, ripple spreads outward from the center |
| `06` | `flowing` | 流光溢彩 | Flowing colors | **Confirmed**, three lines move from left to right |
| `07` | `streamer` | 流光 | Streamer | **Confirmed**, lines close in from both ends toward the center |
| `08` | `key-wave` | 点彩夺目 | Dazzling dots | **Confirmed**, lights stay off until a key press sends a wave out and back |
| `09` | `trigger` | 一触即发 | Trigger on press | **Confirmed**, a key press lights that key's row in a wave |
| `0A` | `snow` | 踏雪无痕 | Snow without trace | **Confirmed**, only the pressed key lights, then turns off |
| `0B` | `key-ripple` | 按键涟漪 | Keypress ripple | **Confirmed**, ripples when typing |
| `0C` | `snake` | 蛇形跑马 | Snake marquee | **Confirmed**, a snake with a complex path |
| `0D` | `blossom` | 花开富贵 | Blossoming | **Confirmed**, a circle blooms, then a line circles the keyboard |
| `0E` | `storm` | 炫装风暴 | Dazzle storm | **Confirmed**, rows sweep in opposite directions, meet, then light the whole keyboard |
| `0F` | `zigzag` | 蛇形跑马 | Snake marquee (same label as `0C`) | **Confirmed**, a snake zigzags through every key |
| `10` | `stars` | 繁星点点 | Starry sky | **Confirmed**, random spots light up |
| `11` | `stream` | 川流不息 | Endless stream | **Confirmed**, rows flow in alternating directions |
| `12` | `diagonal` | 斜拉变换 | Diagonal shift | **Confirmed**, a diagonal line sweeps left and right |
| `13` | `sine` | 正玄光波 | Sine wave | **Confirmed**, a sine wave moves from right to left |

The F2067 project's English effect names do not describe the F2058's behavior.

### Effect motion notes for the GUI preview

These notes record what the owner saw, so a future GUI can animate each effect. A photo of the keyboard with all lights on will supply the key layout and LED colors. After labeling, each effect will run for 10 seconds while the owner records a video as a motion reference.

| Value | Observed motion | Still needed for an accurate preview |
|---|---|---|
| `00` | All keys stay lit with no motion | Nothing |
| `01` | No motion. Byte 6 `00` (`M1`) lights 1 2 3 4 5 Q W E T A S D F Z C V B M, Tab, Shift, Ctrl and Alt. Byte 6 `01` (`M2`) lights 1 2 3 4 5 6 Q W E R Y A S D F G H C B M, Tab, Esc and Space. Byte 6 `02` (`M3`) lights Esc, F1, Ctrl, Shift, Ins, Home, PgUp, Del, End, 1 2 3 4 Q W E R A S D, Space and Enter | Which left or right Shift and Ctrl keys are lit |
| `02` | The backlight flashes, and speed `02` is faster than speed `00` | Hard flash or smooth fade |
| `03` | A key turns off when pressed | How quickly it comes back on |
| `04` | A wave of light moves across the keyboard | Direction |
| `05` | A ripple spreads outward from the center | Whether it repeats by itself or needs a key press |
| `06` | Three lines move from left to right | Line shape, spacing, and how they repeat |
| `07` | Lines move inward from the left and right ends toward the center, shown by the owner as `><><` | Number of lines, and what happens when they meet |
| `08` | All lights stay off. Pressing a key lights the area around it in an outward wave, then the wave closes back in | Wave radius and duration |
| `09` | Pressing a key lights the row that key is on, in a wave-like motion | Wave direction along the row, and whether other keys stay off |
| `0A` | All lights stay off. A pressed key lights by itself, then turns off | How long the key stays lit |
| `0B` | Keys stay lit and ripple when pressed | Ripple size and shape |
| `0C` | A snake moves across the keyboard along a complex path | Exact path, from the video reference |
| `0D` | A circle near the middle turns around the O key and blooms. A line then walks around the keyboard until the next bloom | Timing and line path, from the video reference |
| `0E` | The top 3 rows light from left to right while the bottom 3 rows light from right to left. They reach the ends, return, meet in the middle, then burst to light the whole keyboard | Timing, from the video reference |
| `0F` | A snake starts at the top left and passes through every key. It walks across a row, drops down one row, and zigzags until it ends at the bottom left, then repeats from the start | Snake length and step time, from the video reference |
| `10` | Random spots light up across the keyboard | Spot density and fade timing, from the video reference |
| `11` | Row 1 flows from left to right, row 2 from right to left, and the direction keeps alternating on each row | Whether rows move together or one after another, from the video reference |
| `12` | A diagonal line sweeps from left to right, then from right to left. Its slope flips with the direction, leaning toward the end it is moving to | Line angle and sweep time, from the video reference |
| `13` | A sine wave moves from right to left | Wave height and length, from the video reference |

### Video reference

Source: a 240.8-second 4K video of the keyboard at 24 fps, filmed at brightness `0D` and speed `01`. Effect step `n` starts about `4.1 + 10 × (n - 1)` seconds into the video.

The frames were sampled every 0.6 seconds, so timings are approximate and fast motion may be missed. Hands and the phone's changing exposure also affect some frames.

LED colors are fixed by keyboard zone:

| Zone | Color |
|---|---|
| Esc and F9 to F12 | Blue |
| F1 to F8 | Blue legends with red underglow |
| Number row `1` to `0`, Num | Red |
| Main typing area, `-`, `=`, Backspace | Cyan |
| Q, W, A, S, D | Magenta and purple |
| PrtSc to PgDn | Green |
| Numeric keypad | Yellow |
| Arrow keys and status LEDs | Magenta |

| Value | Video start | What the frames show |
|---|---|---|
| `00` | 4 s | Every key lit, with no motion |
| `01` M1, M2, M3 | 14 s, 24 s, 34 s | Fixed key groups, with no motion |
| `02` | 44 s | The whole keyboard pulses between dim and bright about every 2.4 seconds, without going fully dark |
| `03` | 54 s | Keyboard stays lit, and pressed keys dim briefly |
| `04` | 64 s | Darker bands move across a lit keyboard |
| `05` | 74 s | Darker rings spread across a lit keyboard |
| `06` | 84 s | Darker bands travel across a lit keyboard |
| `07` | 94 s | Darker bands move across a lit keyboard |
| `08` | 104 s | Dark until a key press, then light spreads across most of the keyboard and fades within about a second |
| `09` | 114 s | Dark until a key press, then full-width rows light up and fade |
| `0A` | 124 s | Dark until a key press, then a small patch around each pressed key lights and fades over 1 to 2 seconds |
| `0B` | 134 s | Keyboard stays lit, and subtle ripples appear around pressed keys |
| `0C` | 144 s | A block about 3 rows tall travels left to right across the upper rows, then right to left across the lower rows. One loop takes about 8 seconds |
| `0D` | 154 s | Single rows and row segments light in quick sequence, and the pattern repeats about every 8 seconds |
| `0E` | 164 s | Upper and lower rows fill from opposite sides until the whole keyboard is lit, then it goes dark. One loop takes about 9 seconds |
| `0F` | 174 s | A lit segment moves one row at a time from the function row to the bottom row. One pass takes about 4.8 seconds |
| `10` | 184 s | Keyboard stays mostly lit while individual keys randomly dim and return |
| `11` | 194 s | Rows show moving lit and dark sections, repeating about every 2.4 seconds |
| `12` | 204 s | A wide diagonal band crosses left to right, the keyboard goes dark briefly, then the band returns right to left. One loop takes about 7 seconds |
| `13` | 214 s | A lit sine curve moves from right to left across an otherwise dark keyboard, as corrected by the owner |

Hardware note: the owner reports that each key on the F2058 has one fixed LED color, so RGB colors and per-key colors are out of scope.

Color option test (2026-11-18): `07 FF FF 0B 0D 01 01 00` changed byte 6 from `00` to `01` on key ripple, with no visible change. Byte 6 has not been tested on other effects.
