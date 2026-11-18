import Foundation

/// F2058 packet format. See PROTOCOL.md for the hardware evidence behind each field.
enum AulaProtocol {
    static let vendorID = 0x1A2C
    static let productID = 0x9EF4
    static let reportID: UInt8 = 0x07
    static let packetSize = 8
    static let maxEffect: UInt8 = 0x13
    static let maxBrightness = 13
    /// Hardware testing showed speed values 3 and 4 stop the animation.
    static let maxSpeed = 2
    static let maxSlot = 2

    static func lightingPacket(_ settings: LightingSettings) -> [UInt8]? {
        guard settings.effect <= maxEffect,
              (0...maxBrightness).contains(settings.brightness),
              (0...maxSpeed).contains(settings.speed),
              (0...maxSlot).contains(settings.slot) else { return nil }
        return [reportID, 0xFF, 0xFF, settings.effect, UInt8(settings.brightness),
                UInt8(settings.speed), UInt8(settings.slot), 0x00]
    }

    /// Allowlist: firmware, bootloader and every other unknown packet can never be sent.
    static func isAllowed(_ packet: [UInt8]) -> Bool {
        packet.count == packetSize && packet[0] == reportID && packet[1] == 0xFF && packet[2] == 0xFF
            && packet[3] <= maxEffect && Int(packet[4]) <= maxBrightness
            && Int(packet[5]) <= maxSpeed && Int(packet[6]) <= maxSlot && packet[7] == 0
    }
}

struct LightingSettings: Codable, Equatable {
    var effect: UInt8 = 0x0B
    var brightness = 13
    var speed = 1
    var slot = 0
}

struct EffectInfo: Identifiable {
    let id: UInt8
    let name: String
    let detail: String
    let symbol: String
    var animated = true
    var reactive = false
}

enum EffectCatalog {
    static let all: [EffectInfo] = [
        EffectInfo(id: 0x00, name: "Always On", detail: "Every key glows steadily", symbol: "sun.max.fill", animated: false),
        EffectInfo(id: 0x01, name: "Game Keys", detail: "Lights a stored key group", symbol: "gamecontroller.fill", animated: false),
        EffectInfo(id: 0x02, name: "Breathing", detail: "The whole board pulses", symbol: "lungs.fill"),
        EffectInfo(id: 0x03, name: "Fade on Press", detail: "Keys go dark as you type", symbol: "hand.tap.fill", reactive: true),
        EffectInfo(id: 0x04, name: "Wave", detail: "Light rolls across the board", symbol: "water.waves"),
        EffectInfo(id: 0x05, name: "Water Ripple", detail: "Rings spread from the center", symbol: "circle.circle.fill"),
        EffectInfo(id: 0x06, name: "Flowing Lines", detail: "Three lines run left to right", symbol: "line.3.horizontal"),
        EffectInfo(id: 0x07, name: "Streamer", detail: "Lines close in on the center", symbol: "arrow.right.and.line.vertical.and.arrow.left"),
        EffectInfo(id: 0x08, name: "Key Wave", detail: "Each press sends out a wave", symbol: "dot.radiowaves.left.and.right", reactive: true),
        EffectInfo(id: 0x09, name: "Row Trigger", detail: "A press lights its whole row", symbol: "rectangle.split.3x1.fill", reactive: true),
        EffectInfo(id: 0x0A, name: "Footprints", detail: "Only the pressed key lights", symbol: "shoeprints.fill", reactive: true),
        EffectInfo(id: 0x0B, name: "Key Ripple", detail: "Stays lit and ripples on press", symbol: "drop.circle.fill", reactive: true),
        EffectInfo(id: 0x0C, name: "Snake", detail: "A band of light circles the rows", symbol: "scribble.variable"),
        EffectInfo(id: 0x0D, name: "Blossom", detail: "A bloom, then a walking line", symbol: "camera.macro"),
        EffectInfo(id: 0x0E, name: "Storm", detail: "Rows collide and burst", symbol: "bolt.fill"),
        EffectInfo(id: 0x0F, name: "Zigzag", detail: "Snakes through every key", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill"),
        EffectInfo(id: 0x10, name: "Starlight", detail: "Keys twinkle at random", symbol: "sparkles"),
        EffectInfo(id: 0x11, name: "Stream", detail: "Rows flow in opposite ways", symbol: "arrow.left.arrow.right"),
        EffectInfo(id: 0x12, name: "Diagonal", detail: "A slanted band sweeps across", symbol: "line.diagonal"),
        EffectInfo(id: 0x13, name: "Sine Wave", detail: "A curve drifts right to left", symbol: "waveform.path")
    ]

    static func info(_ id: UInt8) -> EffectInfo { all.first { $0.id == id } ?? all[0] }
}
