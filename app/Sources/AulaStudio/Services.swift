import ApplicationServices
import Carbon.HIToolbox
import Foundation
import IOKit.hid

enum DeviceError: LocalizedError {
    case notConnected, accessDenied, blocked, failed(UInt32)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Keyboard not connected"
        case .accessDenied: "Allow Input Monitoring to control the keyboard"
        case .blocked: "Blocked an unrecognized command"
        case .failed(let code): String(format: "The keyboard rejected the command (%08X)", code)
        }
    }
}

enum DeviceService {
    private static let notPermitted: UInt32 = 0xE00002E2

    static var hasAccess: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    static func requestAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
    }

    /// Interface 1 is the only one with 8-byte output and feature reports.
    private static func configurationInterface() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: AulaProtocol.vendorID,
                                                kIOHIDProductIDKey: AulaProtocol.productID] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        return devices.first {
            intProperty($0, kIOHIDMaxOutputReportSizeKey) == AulaProtocol.packetSize
                && intProperty($0, kIOHIDMaxFeatureReportSizeKey) == AulaProtocol.packetSize
        }
    }

    static var isConnected: Bool { configurationInterface() != nil }

    static func send(_ packet: [UInt8]) throws {
        guard AulaProtocol.isAllowed(packet) else { throw DeviceError.blocked }
        guard let device = configurationInterface() else { throw DeviceError.notConnected }
        // A shared open keeps the keyboard typing while the command is sent.
        let opened = UInt32(bitPattern: IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)))
        if opened == notPermitted { throw DeviceError.accessDenied }
        guard opened == 0 else { throw DeviceError.failed(opened) }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        let result = UInt32(bitPattern: IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(packet[0]), packet, packet.count))
        guard result == 0 else { throw DeviceError.failed(result) }
    }
}

enum MappingService {
    static func payload(_ mappings: [UInt8: UInt8]) -> String {
        let rows = mappings.sorted { $0.key < $1.key }.map { source, target in
            ["HIDKeyboardModifierMappingSrc": 0x7_0000_0000 | Int(source),
             "HIDKeyboardModifierMappingDst": 0x7_0000_0000 | Int(target)]
        }
        let data = try! JSONSerialization.data(withJSONObject: ["UserKeyMapping": rows], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Applies mappings to this keyboard only, leaving the MacBook's built-in keyboard alone.
    static func apply(_ mappings: [UInt8: UInt8]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--matching", "{\"VendorID\":\(AulaProtocol.vendorID),\"ProductID\":\(AulaProtocol.productID)}",
                             "--set", payload(mappings)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AulaStudio", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "macOS could not apply the key mapping"])
        }
    }
}

struct MacroStep: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case text, key, delay }
    var id = UUID()
    var kind: Kind
    var text = ""
    var keyID = "A"
    var command = false
    var control = false
    var option = false
    var shift = false
    var delay = 100
}

struct Macro: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "New Macro"
    var trigger: String?
    var repeatCount = 1
    var steps: [MacroStep] = []
}

private var hotKeyHandler: ((UInt32) -> Void)?

/// A macro key is remapped to an unused function key, which a system hotkey then catches.
final class MacroEngine {
    static let slots: [(usage: UInt8, virtualKey: UInt32)] = [
        (0x6B, 106), (0x6C, 64), (0x6D, 79), (0x6E, 80), (0x6F, 90), (0x68, 105), (0x69, 107), (0x6A, 113)
    ]

    private var hotKeys: [EventHotKeyRef] = []
    private let queue = DispatchQueue(label: "aula.macros")
    private var isRunning = false

    init(onFire: @escaping (Int) -> Void) {
        hotKeyHandler = { id in DispatchQueue.main.async { onFire(Int(id)) } }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            hotKeyHandler?(hotKey.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(count: Int) {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        for slot in 0..<min(count, Self.slots.count) {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x41554C41), id: UInt32(slot))
            if RegisterEventHotKey(Self.slots[slot].virtualKey, 0, id, GetEventDispatcherTarget(), 0, &reference) == noErr,
               let reference { hotKeys.append(reference) }
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func run(_ macro: Macro) {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            defer { isRunning = false }
            for _ in 0..<max(macro.repeatCount, 1) {
                macro.steps.forEach(Self.perform)
            }
        }
    }

    private static func perform(_ step: MacroStep) {
        let source = CGEventSource(stateID: .hidSystemState)
        switch step.kind {
        case .delay:
            Thread.sleep(forTimeInterval: Double(max(step.delay, 0)) / 1000)
        case .text:
            let units = Array(step.text.utf16)
            for start in stride(from: 0, to: units.count, by: 16) {
                let chunk = Array(units[start..<min(start + 16, units.count)])
                for isDown in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown)
                    event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    event?.post(tap: .cghidEventTap)
                }
                Thread.sleep(forTimeInterval: 0.012)
            }
        case .key:
            guard let key = KeyboardLayout.byID[step.keyID]?.virtualKey else { return }
            var flags: CGEventFlags = []
            if step.command { flags.insert(.maskCommand) }
            if step.control { flags.insert(.maskControl) }
            if step.option { flags.insert(.maskAlternate) }
            if step.shift { flags.insert(.maskShift) }
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.012)
            }
        }
    }
}
