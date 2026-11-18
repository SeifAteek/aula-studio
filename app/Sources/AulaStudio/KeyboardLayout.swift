import SwiftUI

/// LED color zones measured from the owner's video of the keyboard.
enum KeyZone {
    case blue, sunset, red, cyan, magenta, green, yellow

    var glow: Color {
        switch self {
        case .blue: Color(red: 0.16, green: 0.36, blue: 1.0)
        case .sunset: Color(red: 1.0, green: 0.13, blue: 0.2)
        case .red: Color(red: 1.0, green: 0.12, blue: 0.18)
        case .cyan: Color(red: 0.2, green: 0.95, blue: 0.86)
        case .magenta: Color(red: 0.93, green: 0.2, blue: 0.98)
        case .green: Color(red: 0.13, green: 0.96, blue: 0.42)
        case .yellow: Color(red: 1.0, green: 0.84, blue: 0.1)
        }
    }

    var legend: Color { self == .sunset ? KeyZone.blue.glow : glow }
}

struct KeyDef: Identifiable {
    let id: String
    let label: String
    let sub: String?
    let name: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let row: Int
    let zone: KeyZone
    let usage: UInt8?
    let virtualKey: UInt16?
    var index = 0

    var centerX: Double { x + w / 2 }
    var centerY: Double { y + h / 2 }
    var normalizedX: Double { centerX / KeyboardLayout.width }
    var normalizedY: Double { centerY / KeyboardLayout.height }
    var canRemap: Bool { usage != nil }
}

enum KeyboardLayout {
    static let width = 22.5
    static let height = 6.25
    private static let rowY = [0, 1.25, 2.25, 3.25, 4.25, 5.25]

    static let keys: [KeyDef] = build()
    static let byID: [String: KeyDef] = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0) })
    static let remappable: [KeyDef] = keys.filter(\.canRemap)

    private static let virtualKeys: [String: UInt16] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12,
        "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "EQUAL": 24, "9": 25, "7": 26, "MINUS": 27, "8": 28, "0": 29, "RBRACKET": 30, "O": 31, "U": 32,
        "LBRACKET": 33, "I": 34, "P": 35, "ENTER": 36, "L": 37, "J": 38, "QUOTE": 39, "K": 40, "SEMICOLON": 41,
        "BACKSLASH": 42, "COMMA": 43, "SLASH": 44, "N": 45, "M": 46, "PERIOD": 47, "TAB": 48, "SPACE": 49,
        "GRAVE": 50, "BACKSPACE": 51, "ESC": 53, "RCMD": 54, "LCMD": 55, "LSHIFT": 56, "CAPSLOCK": 57,
        "LALT": 58, "LCTRL": 59, "RSHIFT": 60, "RALT": 61, "RCTRL": 62, "F5": 96, "F6": 97, "F7": 98, "F3": 99,
        "F8": 100, "F9": 101, "F11": 103, "F10": 109, "F12": 111, "F4": 118, "F2": 120, "F1": 122,
        "PRINTSCREEN": 105, "SCROLLLOCK": 107, "PAUSE": 113, "INSERT": 114, "HOME": 115, "PAGEUP": 116,
        "DELETE": 117, "END": 119, "PAGEDOWN": 121, "LEFT": 123, "RIGHT": 124, "DOWN": 125, "UP": 126,
        "KPDOT": 65, "KPSTAR": 67, "KPPLUS": 69, "NUMLOCK": 71, "KPSLASH": 75, "KPENTER": 76, "KPMINUS": 78,
        "KP0": 82, "KP1": 83, "KP2": 84, "KP3": 85, "KP4": 86, "KP5": 87, "KP6": 88, "KP7": 89, "KP8": 91, "KP9": 92
    ]

    private static func zone(_ id: String) -> KeyZone {
        if id == "ESC" || ["F9", "F10", "F11", "F12"].contains(id) { return .blue }
        if ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8"].contains(id) { return .sunset }
        if ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "NUMLOCK", "KPSLASH", "KPSTAR", "KPMINUS", "KPPLUS", "KPENTER"].contains(id) { return .red }
        if ["Q", "W", "A", "S", "D", "UP", "DOWN", "LEFT", "RIGHT"].contains(id) { return .magenta }
        if ["PRINTSCREEN", "SCROLLLOCK", "PAUSE", "INSERT", "HOME", "PAGEUP", "DELETE", "END", "PAGEDOWN"].contains(id) { return .green }
        if id.hasPrefix("KP") { return .yellow }
        return .cyan
    }

    private static func build() -> [KeyDef] {
        var out: [KeyDef] = []
        func add(_ id: String, _ label: String, _ x: Double, _ row: Int, w: Double = 1, h: Double = 1,
                 sub: String? = nil, name: String? = nil, usage: UInt8?) {
            out.append(KeyDef(id: id, label: label, sub: sub, name: name ?? label, x: x, y: rowY[row], w: w, h: h, row: row,
                              zone: zone(id), usage: usage, virtualKey: virtualKeys[id], index: out.count))
        }
        func letters(_ text: String, from x: Double, row: Int) {
            for (offset, character) in text.enumerated() {
                add(String(character), String(character), x + Double(offset), row,
                    usage: UInt8(character.asciiValue! - 65 + 4))
            }
        }

        add("ESC", "Esc", 0, 0, name: "Escape", usage: 41)
        for (index, x) in [2.0, 3, 4, 5, 6.5, 7.5, 8.5, 9.5, 11, 12, 13, 14].enumerated() {
            add("F\(index + 1)", "F\(index + 1)", x, 0, usage: UInt8(58 + index))
        }
        add("PRINTSCREEN", "PrtSc", 15.25, 0, name: "Print Screen", usage: 70)
        add("SCROLLLOCK", "ScLk", 16.25, 0, name: "Scroll Lock", usage: 71)
        add("PAUSE", "Pause", 17.25, 0, usage: 72)

        add("GRAVE", "`", 0, 1, sub: "~", name: "Backtick", usage: 53)
        let shifted = ["!", "@", "#", "$", "%", "^", "&", "*", "("]
        for digit in 1...9 {
            add("\(digit)", "\(digit)", Double(digit), 1, sub: shifted[digit - 1], usage: UInt8(29 + digit))
        }
        add("0", "0", 10, 1, sub: ")", usage: 39)
        add("MINUS", "-", 11, 1, sub: "_", name: "Minus", usage: 45)
        add("EQUAL", "=", 12, 1, sub: "+", name: "Equals", usage: 46)
        add("BACKSPACE", "⌫", 13, 1, w: 2, name: "Backspace", usage: 42)
        add("INSERT", "Ins", 15.25, 1, name: "Insert", usage: 73)
        add("HOME", "Home", 16.25, 1, usage: 74)
        add("PAGEUP", "PgUp", 17.25, 1, name: "Page Up", usage: 75)
        add("NUMLOCK", "Num", 18.5, 1, name: "Num Lock", usage: 83)
        add("KPSLASH", "/", 19.5, 1, name: "Keypad Divide", usage: 84)
        add("KPSTAR", "*", 20.5, 1, name: "Keypad Multiply", usage: 85)
        add("KPMINUS", "-", 21.5, 1, name: "Keypad Minus", usage: 86)

        add("TAB", "Tab", 0, 2, w: 1.5, usage: 43)
        letters("QWERTYUIOP", from: 1.5, row: 2)
        add("LBRACKET", "[", 11.5, 2, sub: "{", name: "Left Bracket", usage: 47)
        add("RBRACKET", "]", 12.5, 2, sub: "}", name: "Right Bracket", usage: 48)
        add("BACKSLASH", "\\", 13.5, 2, w: 1.5, sub: "|", name: "Backslash", usage: 49)
        add("DELETE", "Del", 15.25, 2, name: "Delete", usage: 76)
        add("END", "End", 16.25, 2, usage: 77)
        add("PAGEDOWN", "PgDn", 17.25, 2, name: "Page Down", usage: 78)
        add("KP7", "7", 18.5, 2, name: "Keypad 7", usage: 95)
        add("KP8", "8", 19.5, 2, name: "Keypad 8", usage: 96)
        add("KP9", "9", 20.5, 2, name: "Keypad 9", usage: 97)
        add("KPPLUS", "+", 21.5, 2, h: 2, name: "Keypad Plus", usage: 87)

        add("CAPSLOCK", "CapsLk", 0, 3, w: 1.75, name: "Caps Lock", usage: 57)
        letters("ASDFGHJKL", from: 1.75, row: 3)
        add("SEMICOLON", ";", 10.75, 3, sub: ":", name: "Semicolon", usage: 51)
        add("QUOTE", "'", 11.75, 3, sub: "\"", name: "Quote", usage: 52)
        add("ENTER", "Enter", 12.75, 3, w: 2.25, usage: 40)
        add("KP4", "4", 18.5, 3, name: "Keypad 4", usage: 92)
        add("KP5", "5", 19.5, 3, name: "Keypad 5", usage: 93)
        add("KP6", "6", 20.5, 3, name: "Keypad 6", usage: 94)

        add("LSHIFT", "Shift", 0, 4, w: 2.25, name: "Left Shift", usage: 225)
        letters("ZXCVBNM", from: 2.25, row: 4)
        add("COMMA", ",", 9.25, 4, sub: "<", name: "Comma", usage: 54)
        add("PERIOD", ".", 10.25, 4, sub: ">", name: "Period", usage: 55)
        add("SLASH", "/", 11.25, 4, sub: "?", name: "Slash", usage: 56)
        add("RSHIFT", "Shift", 12.25, 4, w: 2.75, name: "Right Shift", usage: 229)
        add("UP", "↑", 16.25, 4, name: "Up Arrow", usage: 82)
        add("KP1", "1", 18.5, 4, name: "Keypad 1", usage: 89)
        add("KP2", "2", 19.5, 4, name: "Keypad 2", usage: 90)
        add("KP3", "3", 20.5, 4, name: "Keypad 3", usage: 91)
        add("KPENTER", "⏎", 21.5, 4, h: 2, name: "Keypad Enter", usage: 88)

        add("LCTRL", "Ctrl", 0, 5, w: 1.25, name: "Left Control", usage: 224)
        add("LCMD", "⊞", 1.25, 5, w: 1.25, name: "Windows Key", usage: 227)
        add("LALT", "Alt", 2.5, 5, w: 1.25, name: "Left Alt", usage: 226)
        add("SPACE", "", 3.75, 5, w: 6.25, name: "Space", usage: 44)
        add("RALT", "Alt", 10, 5, w: 1.25, name: "Right Alt", usage: 230)
        add("FN", "Fn", 11.25, 5, w: 1.25, name: "Function", usage: nil)
        add("MENU", "☰", 12.5, 5, w: 1.25, name: "Menu", usage: 101)
        add("RCTRL", "Ctrl", 13.75, 5, w: 1.25, name: "Right Control", usage: 228)
        add("LEFT", "←", 15.25, 5, name: "Left Arrow", usage: 80)
        add("DOWN", "↓", 16.25, 5, name: "Down Arrow", usage: 81)
        add("RIGHT", "→", 17.25, 5, name: "Right Arrow", usage: 79)
        add("KP0", "0", 18.5, 5, w: 2, name: "Keypad 0", usage: 98)
        add("KPDOT", ".", 20.5, 5, name: "Keypad Decimal", usage: 99)
        return out
    }

    /// Key groups the owner observed for the three factory slots.
    static let slotKeys: [Set<String>] = [
        ["1", "2", "3", "4", "5", "Q", "W", "E", "T", "A", "S", "D", "F", "Z", "C", "V", "B", "M", "TAB", "LSHIFT", "LCTRL", "LALT"],
        ["1", "2", "3", "4", "5", "6", "Q", "W", "E", "R", "Y", "A", "S", "D", "F", "G", "H", "C", "B", "M", "TAB", "ESC", "SPACE"],
        ["ESC", "F1", "LCTRL", "LSHIFT", "INSERT", "HOME", "PAGEUP", "DELETE", "END", "1", "2", "3", "4", "Q", "W", "E", "R", "A", "S", "D", "SPACE", "ENTER"]
    ]
}
