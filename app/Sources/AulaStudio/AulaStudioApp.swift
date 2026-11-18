import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-check") {
            SelfCheck.run()
        } else if let flag = arguments.firstIndex(of: "--write-icon"), arguments.count > flag + 1 {
            MainActor.assumeIsolated { AppIcon.write(to: arguments[flag + 1]) }
        } else {
            AulaStudioApp.main()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Macros keep working from the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct AulaStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel = {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--demo-tab"), arguments.count > flag + 1 {
            return AppModel.demo(tab: arguments[flag + 1])
        }
        return AppModel()
    }()

    var body: some Scene {
        Window("AULA Studio", id: "main") {
            ContentView()
                .environment(model)
                .onAppear {
                    // Screenshot mode stays above other windows so only the app can be captured.
                    guard CommandLine.arguments.contains("--demo-tab") else { return }
                    NSApp.activate()
                    DispatchQueue.main.async { NSApp.windows.forEach { $0.level = .floating } }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1440, height: 940)
        .windowResizability(.contentMinSize)

        MenuBarExtra("AULA Studio", systemImage: "keyboard") {
            MenuBarContent()
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open AULA Studio") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        Button("Quit AULA Studio") { NSApp.terminate(nil) }
    }
}

enum SelfCheck {
    static func run() {
        let keys = KeyboardLayout.keys
        precondition(keys.count == 104, "layout must have 104 keys")
        precondition(Set(keys.map(\.id)).count == 104, "key ids must be unique")
        precondition(keys.enumerated().allSatisfy { $0.offset == $0.element.index }, "key indexes must match")
        precondition(keys.filter { !$0.canRemap }.map(\.id) == ["FN"], "only Fn is firmware-only")
        precondition(Set(keys.compactMap(\.usage)).count == 103, "HID usages must be unique")
        precondition(keys.filter { $0.virtualKey == nil }.map(\.id).sorted() == ["FN", "MENU"], "virtual keys must be complete")
        precondition(KeyboardLayout.slotKeys.joined().allSatisfy { KeyboardLayout.byID[$0] != nil }, "slot keys must exist")

        let confirmed = LightingSettings(effect: 0x0B, brightness: 13, speed: 1, slot: 0)
        precondition(AulaProtocol.lightingPacket(confirmed) == [0x07, 0xFF, 0xFF, 0x0B, 0x0D, 0x01, 0x00, 0x00], "confirmed packet changed")
        let slot = LightingSettings(effect: 0x01, brightness: 13, speed: 1, slot: 2)
        precondition(AulaProtocol.lightingPacket(slot) == [0x07, 0xFF, 0xFF, 0x01, 0x0D, 0x01, 0x02, 0x00], "M3 packet changed")
        for bad in [LightingSettings(effect: 0x14), LightingSettings(brightness: 14), LightingSettings(speed: 3), LightingSettings(slot: 3)] {
            precondition(AulaProtocol.lightingPacket(bad) == nil, "out-of-range settings must be rejected")
        }
        for blocked: [UInt8] in [[0x07, 0xF0, 0xAA, 0, 0, 0, 0, 0], [0x07, 0xF1, 0, 0, 0, 0, 0, 0], [0x07, 0xFF, 0xFF, 0x20, 0, 0, 0, 0],
                                 [0x07, 0xFF, 0xFF, 0x02, 0x0D, 0x03, 0, 0], [0x07, 0xFF, 0xFF, 0]] {
            precondition(!AulaProtocol.isAllowed(blocked), "unknown packets must be blocked")
        }

        for effect in EffectCatalog.all {
            for key in keys {
                for time in stride(from: 0.0, to: 20.0, by: 0.37) {
                    let value = EffectEngine.intensity(effect: effect.id, key: key, now: time, speed: 4, slot: 2,
                                                       presses: EffectEngine.demoPresses(now: time))
                    precondition((0...1).contains(value), "effect \(effect.id) returned \(value)")
                }
            }
        }
        precondition(MappingService.payload([57: 41]).contains("30064771129"), "CapsLock source changed")
        precondition(MappingService.payload([57: 41]).contains("30064771113"), "Esc target changed")
        print("Self-check passed: 104 keys, 20 effects, packets and mappings verified.")
    }
}

@MainActor
enum AppIcon {
    static func write(to path: String) {
        let renderer = ImageRenderer(content: IconArtwork().frame(width: 1024, height: 1024))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            fatalError("Could not render the app icon")
        }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch { fatalError("Could not write the app icon: \(error)") }
    }
}

private struct IconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 228, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.16), Color(red: 0.01, green: 0.01, blue: 0.04)], startPoint: .top, endPoint: .bottom))
                .padding(52)
            Circle().fill(KeyZone.cyan.glow).frame(width: 420).blur(radius: 110).offset(x: -150, y: 170).opacity(0.9)
            Circle().fill(KeyZone.magenta.glow).frame(width: 400).blur(radius: 110).offset(x: 180, y: 130).opacity(0.85)
            Circle().fill(KeyZone.blue.glow).frame(width: 380).blur(radius: 110).offset(x: 50, y: -210).opacity(0.8)
            RoundedRectangle(cornerRadius: 118, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 118, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 9))
                .frame(width: 540, height: 540)
                .shadow(color: .black.opacity(0.5), radius: 44, y: 28)
            Text("A")
                .font(.system(size: 370, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.62, green: 1, blue: 0.96)], startPoint: .top, endPoint: .bottom))
                .shadow(color: KeyZone.cyan.glow.opacity(0.85), radius: 38)
        }
        .clipShape(RoundedRectangle(cornerRadius: 228, style: .continuous).inset(by: 52))
    }
}
