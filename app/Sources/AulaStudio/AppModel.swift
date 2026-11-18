import AppKit
import Observation
import ServiceManagement
import SwiftUI

struct Profile: Codable, Equatable {
    var lighting = LightingSettings()
    var remaps: [String: String] = [:]
    var macros: [Macro] = []
}

struct Store: Codable, Equatable {
    var active = 0
    var profiles = [Profile(), Profile(), Profile()]
}

enum StudioTab: String, CaseIterable, Identifiable {
    case lighting = "Lighting", mapping = "Key Mapping", macros = "Macros"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .lighting: "sparkles"
        case .mapping: "keyboard"
        case .macros: "bolt.horizontal.fill"
        }
    }
}

enum AppClock {
    static let start = Date()
    static func now(_ date: Date = Date()) -> Double { date.timeIntervalSince(start) }
}

@MainActor
@Observable
final class AppModel {
    var tab: StudioTab = .lighting { didSet { mappingSource = nil; capturingTrigger = false } }
    var connected = false
    var hasAccess = false
    var macrosTrusted = false
    var mappingSource: String?
    var hoveredKey: String?
    var selectedMacro: UUID?
    var capturingTrigger = false
    var toast: String?
    var presses: [KeyPress] = []
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    var store: Store {
        didSet {
            guard store != oldValue, live else { return }
            persist()
            if effectiveMappings(for: oldValue) != effectiveMappings(for: store) { applyMappings() }
        }
    }

    @ObservationIgnored private let live: Bool
    private var sendTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var pollTimer: Timer?
    @ObservationIgnored private lazy var macroEngine = MacroEngine { [weak self] slot in self?.fireMacro(slot) }

    private static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AULA Studio/state.json")
    }

    /// `live: false` renders the interface without touching the keyboard, macOS mappings or saved settings.
    init(live: Bool = true) {
        self.live = live
        store = live ? Self.loadStore() : Store()
        refreshStatus()
        guard live else { return }
        applyMappings()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
    }

    /// Sample data for product screenshots. It never touches the keyboard or saved settings.
    static func demo(tab: String) -> AppModel {
        let model = AppModel(live: false)
        model.tab = StudioTab.allCases.first { $0.rawValue.lowercased().hasPrefix(tab.lowercased()) } ?? .lighting
        model.connected = true
        model.hasAccess = true
        model.macrosTrusted = true
        model.profile.lighting = LightingSettings(effect: 0x06, brightness: 13, speed: 1, slot: 0)
        model.profile.remaps = ["CAPSLOCK": "ESC", "F1": "F2", "RALT": "LCTRL"]
        var macro = Macro()
        macro.name = "Email Signature"
        macro.trigger = "F5"
        macro.steps = [MacroStep(kind: .text, text: "Best regards,"), MacroStep(kind: .delay),
                       MacroStep(kind: .key, keyID: "ENTER", shift: true)]
        model.profile.macros = [macro]
        model.selectedMacro = macro.id
        return model
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            show("macOS couldn't change Launch at Login")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func loadStore() -> Store {
        if let data = try? Data(contentsOf: storeURL), var saved = try? JSONDecoder().decode(Store.self, from: data),
           saved.profiles.count == 3, saved.profiles.indices.contains(saved.active) {
            // Profiles saved during speed testing may hold values the keyboard doesn't support.
            for index in saved.profiles.indices {
                saved.profiles[index].lighting.speed = min(saved.profiles[index].lighting.speed, AulaProtocol.maxSpeed)
            }
            return saved
        }
        // First launch: keep any remaps already made with the command-line tool.
        var fresh = Store()
        let cliState = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aula/state.json")
        if let data = try? Data(contentsOf: cliState),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let remaps = json["remaps"] as? [String: String] {
            fresh.profiles[0].remaps = remaps.filter { KeyboardLayout.byID[$0.key]?.canRemap == true && KeyboardLayout.byID[$0.value]?.canRemap == true }
        }
        return fresh
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: Self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(store).write(to: Self.storeURL, options: .atomic)
        } catch {
            show("Could not save your settings")
        }
    }

    var profile: Profile {
        get { store.profiles[store.active] }
        set { store.profiles[store.active] = newValue }
    }

    var lighting: LightingSettings { profile.lighting }

    // MARK: Status

    func refreshStatus() {
        let wasConnected = connected
        connected = DeviceService.isConnected
        hasAccess = DeviceService.hasAccess
        macrosTrusted = MacroEngine.isTrusted
        // macOS clears a device's key mappings when the keyboard reconnects.
        if connected && !wasConnected { applyMappings() }
    }

    func requestInputMonitoring() {
        DeviceService.requestAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func requestAccessibility() { MacroEngine.promptForTrust() }

    func show(_ message: String) {
        withAnimation(.smooth) { toast = message }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { self?.toast = nil }
        }
    }

    // MARK: Lighting

    func updateLighting(_ change: (inout LightingSettings) -> Void) {
        change(&profile.lighting)
        scheduleSend()
    }

    /// The driver leaves at least 100 ms between commands, so rapid slider changes are merged.
    private func scheduleSend() {
        guard live else { return }
        sendTask?.cancel()
        let settings = lighting
        sendTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let packet = AulaProtocol.lightingPacket(settings) else { return }
            do {
                try DeviceService.send(packet)
            } catch {
                self?.show(error.localizedDescription)
            }
        }
    }

    func selectProfile(_ index: Int) {
        guard store.profiles.indices.contains(index), index != store.active else { return }
        store.active = index
        mappingSource = nil
        selectedMacro = nil
        capturingTrigger = false
        scheduleSend()
    }

    // MARK: Keyboard taps

    func tap(_ key: KeyDef) {
        switch tab {
        case .lighting:
            presses.append(KeyPress(keyIndex: key.index, time: AppClock.now()))
            presses.removeAll { AppClock.now() - $0.time > 3 }
        case .mapping:
            tapForMapping(key)
        case .macros:
            guard capturingTrigger else { return }
            setTrigger(key)
        }
    }

    private func tapForMapping(_ key: KeyDef) {
        guard key.canRemap else { return show("\(key.name) is handled inside the keyboard") }
        guard let source = mappingSource else {
            mappingSource = key.id
            return
        }
        mappingSource = nil
        guard source != key.id else { return }
        for index in profile.macros.indices where profile.macros[index].trigger == source {
            profile.macros[index].trigger = nil
        }
        profile.remaps[source] = key.id
        show("\(KeyboardLayout.byID[source]?.name ?? source) now acts as \(key.name)")
    }

    func removeRemap(_ source: String) { profile.remaps[source] = nil }

    func clearRemaps() {
        profile.remaps.removeAll()
        mappingSource = nil
    }

    // MARK: Mappings

    private func effectiveMappings(for store: Store) -> [UInt8: UInt8] {
        let profile = store.profiles[store.active]
        var mappings: [UInt8: UInt8] = [:]
        for (source, target) in profile.remaps {
            if let from = KeyboardLayout.byID[source]?.usage, let to = KeyboardLayout.byID[target]?.usage { mappings[from] = to }
        }
        for (slot, macro) in triggeredMacros(profile).enumerated() {
            if let trigger = macro.trigger, let from = KeyboardLayout.byID[trigger]?.usage { mappings[from] = MacroEngine.slots[slot].usage }
        }
        return mappings
    }

    private func triggeredMacros(_ profile: Profile) -> [Macro] {
        Array(profile.macros.filter { $0.trigger != nil }.prefix(MacroEngine.slots.count))
    }

    private func applyMappings() {
        let mappings = effectiveMappings(for: store)
        macroEngine.register(count: triggeredMacros(profile).count)
        Task.detached { [weak self] in
            do {
                try MappingService.apply(mappings)
            } catch {
                await self?.show(error.localizedDescription)
            }
        }
    }

    // MARK: Macros

    func addMacro() {
        guard profile.macros.count < MacroEngine.slots.count else { return show("Each profile can hold \(MacroEngine.slots.count) macros") }
        var macro = Macro()
        macro.name = "Macro \(profile.macros.count + 1)"
        macro.steps = [MacroStep(kind: .text, text: "Hello from AULA")]
        profile.macros.append(macro)
        selectedMacro = macro.id
    }

    func deleteMacro(_ id: UUID) {
        profile.macros.removeAll { $0.id == id }
        if selectedMacro == id { selectedMacro = profile.macros.first?.id }
        capturingTrigger = false
    }

    private func setTrigger(_ key: KeyDef) {
        guard key.canRemap, let id = selectedMacro, let index = profile.macros.firstIndex(where: { $0.id == id }) else {
            return show("\(key.name) can't start a macro")
        }
        for other in profile.macros.indices where profile.macros[other].trigger == key.id { profile.macros[other].trigger = nil }
        profile.remaps[key.id] = nil
        profile.macros[index].trigger = key.id
        capturingTrigger = false
        if !macrosTrusted { requestAccessibility() }
        show("\(key.name) now runs \(profile.macros[index].name)")
    }

    private func fireMacro(_ slot: Int) {
        let macros = triggeredMacros(profile)
        guard macros.indices.contains(slot) else { return }
        guard MacroEngine.isTrusted else {
            requestAccessibility()
            return show("Allow Accessibility so macros can type")
        }
        macroEngine.run(macros[slot])
    }
}
