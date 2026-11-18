import Foundation

struct KeyPress {
    let keyIndex: Int
    let time: Double
}

/// Approximates each firmware effect from the owner's descriptions and video. Returns 0...1 per key.
enum EffectEngine {
    static let speedFactors = [0.55, 1.0, 1.6]

    private static func band(_ distance: Double, _ width: Double) -> Double {
        exp(-(distance * distance) / (width * width))
    }

    private static func fract(_ value: Double) -> Double { value - floor(value) }

    private static func wrappedDistance(_ a: Double, _ b: Double) -> Double {
        let distance = abs(fract(a) - fract(b))
        return min(distance, 1 - distance)
    }

    private static func hash(_ value: Int, _ salt: Double) -> Double {
        fract(sin(Double(value) * 127.1 + salt * 311.7) * 43758.5453)
    }

    private static func distance(_ key: KeyDef, _ other: KeyDef) -> Double {
        let dx = key.normalizedX - other.normalizedX
        let dy = (key.normalizedY - other.normalizedY) * KeyboardLayout.height / KeyboardLayout.width
        return sqrt(dx * dx + dy * dy)
    }

    /// Reactive effects need presses, so the preview types by itself between real clicks.
    static func demoPresses(now: Double) -> [KeyPress] {
        let letters = KeyboardLayout.keys.filter { $0.id.count == 1 && $0.id.first!.isLetter }
        let step = 0.62
        let tick = Int(floor(now / step))
        return (0..<5).map { offset in
            let beat = tick - offset
            let pick = Int(hash(beat, 1.3) * Double(letters.count)) % letters.count
            return KeyPress(keyIndex: letters[pick].index, time: Double(beat) * step)
        }
    }

    static func intensity(effect: UInt8, key: KeyDef, now: Double, speed: Int, slot: Int, presses: [KeyPress]) -> Double {
        let t = now * speedFactors[min(max(speed, 0), speedFactors.count - 1)]
        let x = key.normalizedX, y = key.normalizedY
        let value: Double
        switch effect {
        case 0x00:
            value = 1
        case 0x01:
            value = KeyboardLayout.slotKeys[min(max(slot, 0), 2)].contains(key.id) ? 1 : 0
        case 0x02:
            value = 0.16 + 0.84 * pow(0.5 + 0.5 * sin(2 * .pi * t / 2.4), 1.6)
        case 0x03:
            let dim = presses.filter { $0.keyIndex == key.index }.map { exp(-max(now - $0.time, 0) / 0.45) }.max() ?? 0
            value = 1 - dim
        case 0x04:
            value = 1 - 0.82 * band(wrappedDistance(x, t / 3.2), 0.14)
        case 0x05:
            let dx = x - 0.5, dy = (y - 0.5) * KeyboardLayout.height / KeyboardLayout.width
            value = 0.22 + 0.78 * pow(0.5 + 0.5 * cos(2 * .pi * (sqrt(dx * dx + dy * dy) * 3 - t / 1.6)), 1.5)
        case 0x06:
            value = 0.14 + 0.86 * band(wrappedDistance(x * 3, t / 1.6 + 0.5), 0.2)
        case 0x07:
            value = 0.14 + 0.86 * band(wrappedDistance(abs(x - 0.5) * 4, -t / 1.8 + 0.5), 0.22)
        case 0x08:
            var peak = 0.0
            for press in presses {
                let age = now - press.time
                guard age >= 0, age < 0.95 else { continue }
                let radius = 0.26 * sin(.pi * age / 0.95)
                let reach = distance(key, KeyboardLayout.keys[press.keyIndex])
                if reach < radius { peak = max(peak, 1 - 0.4 * reach / max(radius, 0.001)) }
            }
            value = peak
        case 0x09:
            var peak = 0.0
            for press in presses {
                let origin = KeyboardLayout.keys[press.keyIndex]
                guard origin.row == key.row else { continue }
                let delay = abs(x - origin.normalizedX) / 1.3
                let age = now - press.time - delay
                if age >= 0 { peak = max(peak, exp(-age / 0.5)) }
            }
            value = peak
        case 0x0A:
            value = presses.filter { $0.keyIndex == key.index }.map { exp(-max(now - $0.time, 0) / 0.6) }.max() ?? 0
        case 0x0B:
            var dim = 0.0
            for press in presses {
                let age = now - press.time
                guard age >= 0 else { continue }
                let ring = band(distance(key, KeyboardLayout.keys[press.keyIndex]) - age * 0.55, 0.045)
                dim = max(dim, ring * exp(-age / 0.8))
            }
            value = 1 - 0.8 * dim
        case 0x0C:
            let phase = fract(t / 8)
            value = phase < 0.5
                ? (key.row <= 2 ? band(x - (phase * 2 * 1.5 - 0.25), 0.17) : 0)
                : (key.row >= 3 ? band(x - (1.25 - (phase - 0.5) * 2 * 1.5), 0.17) : 0)
        case 0x0D:
            value = blossom(key: key, phase: fract(t / 8))
        case 0x0E:
            value = storm(key: key, phase: fract(t / 9))
        case 0x0F:
            let path = fract(t / 4.8) * 6
            let row = Int(floor(path))
            guard key.row == row else { return 0 }
            let head = row % 2 == 0 ? path - Double(row) : 1 - (path - Double(row))
            let behind = row % 2 == 0 ? head - x : x - head
            value = behind >= -0.03 && behind < 0.42 ? 1 - max(behind, 0) / 0.42 : 0
        case 0x10:
            let twinkle = 0.5 + 0.5 * sin(2 * .pi * (t * (0.28 + hash(key.index, 2.1) * 0.5) + hash(key.index, 4.7)))
            value = twinkle < 0.35 ? 0.1 + twinkle * 1.6 : 0.66 + twinkle * 0.34
        case 0x11:
            let direction = key.row % 2 == 0 ? -1.0 : 1.0
            value = 0.1 + 0.9 * band(wrappedDistance(x * 1.5, direction * t / 2.4), 0.26)
        case 0x12:
            value = diagonal(x: x, y: y, phase: fract(t / 7))
        case 0x13:
            let curve = 0.5 + 0.34 * sin(2 * .pi * (x * 1.4 + t / 2.8))
            value = band(y - curve, 0.17)
        default:
            value = 0
        }
        return min(max(value, 0), 1)
    }

    private static func blossom(key: KeyDef, phase: Double) -> Double {
        let center = KeyboardLayout.byID["O"]!
        if phase < 0.35 {
            return band(distance(key, center) - phase / 0.35 * 0.32, 0.05)
        }
        let walk = (phase - 0.35) / 0.65
        let x = key.normalizedX, y = key.normalizedY
        let position: Double
        if key.row == 0 { position = x * 0.35 }
        else if x > 0.93 { position = 0.35 + y * 0.15 }
        else if key.row == 5 { position = 0.5 + (1 - x) * 0.35 }
        else if x < 0.07 { position = 0.85 + (1 - y) * 0.15 }
        else { return 0 }
        return band(wrappedDistance(position, walk), 0.07)
    }

    private static func storm(key: KeyDef, phase: Double) -> Double {
        let x = key.normalizedX
        let travel = key.row <= 2 ? x : 1 - x
        if phase < 0.35 { return travel < phase / 0.35 ? 1 : 0 }
        if phase < 0.6 { return band(travel - (1 - (phase - 0.35) / 0.25 * 0.5), 0.12) }
        if phase < 0.85 { return 1 }
        return max(0, 1 - (phase - 0.85) / 0.06)
    }

    private static func diagonal(x: Double, y: Double, phase: Double) -> Double {
        let lean = (y - 0.5) * 0.32
        if phase < 0.42 { return band(x + lean - (phase / 0.42 * 1.7 - 0.35), 0.17) }
        if phase >= 0.5, phase < 0.92 { return band(x - lean - (1.35 - (phase - 0.5) / 0.42 * 1.7), 0.17) }
        return 0
    }
}
