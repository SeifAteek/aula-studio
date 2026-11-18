import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 8) {
                HeaderBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                KeyboardStage()
                    .frame(minHeight: 300, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                Group {
                    switch model.tab {
                    case .lighting: LightingPanel()
                    case .mapping: MappingPanel()
                    case .macros: MacrosPanel()
                    }
                }
                .transition(.blurReplace)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .animation(.smooth(duration: 0.32), value: model.tab)

            if let toast = model.toast {
                VStack {
                    Spacer()
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(minWidth: 1180, minHeight: 800)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

private struct AmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = Float(AppClock.now(timeline.date)) * 0.16
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5 + 0.09 * sin(t)], [0.5 + 0.14 * cos(t * 0.8), 0.48 + 0.1 * sin(t * 1.2)], [1, 0.5 + 0.09 * cos(t)],
                [0, 1], [0.5 + 0.1 * sin(t * 0.7), 1], [1, 1]
            ], colors: [
                Color(red: 0.02, green: 0.03, blue: 0.1), Color(red: 0.02, green: 0.09, blue: 0.13), Color(red: 0.09, green: 0.03, blue: 0.13),
                Color(red: 0.03, green: 0.13, blue: 0.18), Color(red: 0.015, green: 0.02, blue: 0.045), Color(red: 0.16, green: 0.04, blue: 0.2),
                Color(red: 0.0, green: 0.13, blue: 0.12), Color(red: 0.05, green: 0.04, blue: 0.14), Color(red: 0.13, green: 0.08, blue: 0.03)
            ])
        }
        .ignoresSafeArea()
    }
}

private struct HeaderBar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var tabSpace

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("AULA STUDIO")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(2.6)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.95, blue: 0.95)], startPoint: .leading, endPoint: .trailing))
                Text("Wind F2058")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.leading, 74)
            Spacer()
            HStack(spacing: 10) {
                ProfileSwitcher()
                StatusPill()
                SettingsButton()
            }
        }
        .frame(height: 48)
        .overlay {
            HStack(spacing: 3) {
                ForEach(StudioTab.allCases) { tab in
                    Button {
                        withAnimation(.bouncy(duration: 0.42, extraBounce: 0.08)) { model.tab = tab }
                    } label: {
                        Label(tab.rawValue, systemImage: tab.symbol)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 17)
                            .padding(.vertical, 9)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.66))
                    .background {
                        if model.tab == tab {
                            Capsule()
                                .fill(.white.opacity(0.17))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.7))
                                .matchedGeometryEffect(id: "selectedTab", in: tabSpace)
                        }
                    }
                    .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

private struct ProfileSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Button("P\(index + 1)") {
                    withAnimation(.smooth) { model.selectProfile(index) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 34, height: 28)
                .foregroundStyle(model.store.active == index ? .black : .white.opacity(0.72))
                .background(model.store.active == index ? Color.white.opacity(0.9) : .clear, in: Capsule())
                .contentShape(Capsule())
                .accessibilityLabel("Profile \(index + 1)")
                .accessibilityAddTraits(model.store.active == index ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct SettingsButton: View {
    @Environment(AppModel.self) private var model
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Settings")
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Keeps your mappings and macros ready after a restart.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 270)
        }
    }
}

private struct StatusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.hasAccess {
                Button {
                    model.requestInputMonitoring()
                } label: {
                    Label("Allow Access", systemImage: "lock.open.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
            } else {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.connected ? KeyZone.green.glow : .orange)
                        .frame(width: 8, height: 8)
                        .shadow(color: model.connected ? KeyZone.green.glow : .orange, radius: 5)
                    Text(model.connected ? "Connected" : "Not Connected")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

// MARK: Lighting

private struct LightingPanel: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            EffectGallery()
            LightingControls()
                .frame(width: 330)
        }
        .frame(height: 248)
    }
}

private struct EffectGallery: View {
    @Environment(AppModel.self) private var model
    private let accents: [KeyZone] = [.cyan, .magenta, .green, .yellow, .blue, .red]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: [GridItem(.fixed(118), spacing: 10), GridItem(.fixed(118), spacing: 10)], spacing: 10) {
                ForEach(Array(EffectCatalog.all.enumerated()), id: \.element.id) { index, effect in
                    EffectCard(effect: effect, accent: accents[index % accents.count].glow,
                               isSelected: model.lighting.effect == effect.id) {
                        withAnimation(.bouncy(duration: 0.34)) { model.updateLighting { $0.effect = effect.id } }
                    }
                }
            }
            .padding(2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct EffectCard: View {
    let effect: EffectInfo
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: effect.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : accent)
                        .symbolEffect(.bounce, value: isSelected)
                        .frame(height: 24)
                    Spacer()
                    if effect.reactive {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                            .accessibilityLabel("Reacts to typing")
                    }
                }
                Spacer(minLength: 0)
                Text(effect.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(effect.detail)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 150, height: 118, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(accent.opacity(0.52)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 20))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(effect.detail)
    }
}

private struct LightingControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 9) {
                ControlHeader(title: "Brightness", symbol: "sun.max.fill", value: "\(model.lighting.brightness) of 13")
                StepSlider(value: model.lighting.brightness, maximum: AulaProtocol.maxBrightness, label: "Brightness") { level in
                    model.updateLighting { $0.brightness = level }
                }
            }
            if model.lighting.effect == 0x01 {
                VStack(alignment: .leading, spacing: 9) {
                    ControlHeader(title: "Key Group", symbol: "gamecontroller.fill", value: "M\(model.lighting.slot + 1)")
                    HStack(spacing: 8) {
                        ForEach(0...AulaProtocol.maxSlot, id: \.self) { slot in
                            Button("M\(slot + 1)") { model.updateLighting { $0.slot = slot } }
                                .buttonStyle(.plain)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(model.lighting.slot == slot ? .black : .white)
                                .background(model.lighting.slot == slot ? Color.white.opacity(0.92) : .white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                                .contentShape(RoundedRectangle(cornerRadius: 13))
                                .accessibilityAddTraits(model.lighting.slot == slot ? .isSelected : [])
                        }
                    }
                }
                .transition(.blurReplace)
            } else {
                SpeedControl()
                    .transition(.blurReplace)
            }
            Spacer(minLength: 0)
            Text(EffectCatalog.info(model.lighting.effect).name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

private struct ControlHeader: View {
    let title: String
    let symbol: String
    let value: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

private struct StepSlider: View {
    let value: Int
    let maximum: Int
    let label: String
    let onChange: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let thumb: CGFloat = 24
            let travel = max(proxy.size.width - thumb, 1)
            let position = CGFloat(value) / CGFloat(maximum) * travel
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 9)
                Capsule()
                    .fill(LinearGradient(colors: [KeyZone.blue.glow, KeyZone.cyan.glow, .white], startPoint: .leading, endPoint: .trailing))
                    .frame(width: position + thumb / 2, height: 9)
                    .shadow(color: KeyZone.cyan.glow.opacity(0.65), radius: 8)
                ForEach(0...maximum, id: \.self) { step in
                    Circle()
                        .fill(.white.opacity(step <= value ? 0.75 : 0.32))
                        .frame(width: 3, height: 3)
                        .offset(x: thumb / 2 - 1.5 + CGFloat(step) / CGFloat(maximum) * travel)
                }
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                    .offset(x: position)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let raw = (drag.location.x - thumb / 2) / travel * CGFloat(maximum)
                let level = min(max(Int(raw.rounded()), 0), maximum)
                if level != value { onChange(level) }
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(value) of \(maximum)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 1, maximum))
            case .decrement: onChange(max(value - 1, 0))
            @unknown default: break
            }
        }
    }
}

private struct SpeedControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let animated = EffectCatalog.info(model.lighting.effect).animated
        VStack(alignment: .leading, spacing: 9) {
            ControlHeader(title: "Speed", symbol: "gauge.with.dots.needle.67percent", value: "\(model.lighting.speed + 1) of \(AulaProtocol.maxSpeed + 1)")
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(0...AulaProtocol.maxSpeed, id: \.self) { level in
                    Button {
                        withAnimation(.bouncy(duration: 0.3)) { model.updateLighting { $0.speed = level } }
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(level <= model.lighting.speed
                                  ? AnyShapeStyle(LinearGradient(colors: [KeyZone.cyan.glow, KeyZone.magenta.glow], startPoint: .bottomLeading, endPoint: .topTrailing))
                                  : AnyShapeStyle(.white.opacity(0.13)))
                            .frame(height: 14 + CGFloat(level) * 13)
                            .frame(maxWidth: .infinity, minHeight: 42, alignment: .bottom)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speed \(level + 1) of \(AulaProtocol.maxSpeed + 1)")
                    .accessibilityAddTraits(model.lighting.speed == level ? .isSelected : [])
                }
            }
        }
        .opacity(animated ? 1 : 0.42)
        .disabled(!animated)
    }
}

// MARK: Key mapping

private struct MappingPanel: View {
    @Environment(AppModel.self) private var model

    private var sourceName: String? { model.mappingSource.flatMap { KeyboardLayout.byID[$0]?.name } }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: sourceName == nil ? "cursorarrow.click.2" : "arrow.right.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(KeyZone.cyan.glow)
                    .contentTransition(.symbolEffect(.replace))
                Text(sourceName.map { "What should \($0) do?" } ?? "Choose a key to change")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceName == nil ? "Click any key on the keyboard above." : "Click the key it should act as.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
                if sourceName != nil {
                    Button("Cancel") { model.mappingSource = nil }
                        .buttonStyle(.glass)
                }
            }
            .padding(20)
            .frame(width: 330, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your Mappings")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Spacer()
                    if !model.profile.remaps.isEmpty {
                        Button("Clear All", role: .destructive) { withAnimation(.smooth) { model.clearRemaps() } }
                            .buttonStyle(.glass)
                    }
                }
                if model.profile.remaps.isEmpty {
                    ContentUnavailableView("No Mappings Yet", systemImage: "keyboard", description: Text("Changes apply to this keyboard only."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 8)], spacing: 8) {
                            ForEach(model.profile.remaps.sorted { $0.key < $1.key }, id: \.key) { source, target in
                                MappingRow(source: source, target: target)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
        .frame(height: 248)
    }
}

private struct MappingRow: View {
    @Environment(AppModel.self) private var model
    let source: String
    let target: String

    var body: some View {
        HStack(spacing: 9) {
            KeyChip(id: source)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(KeyZone.cyan.glow)
            KeyChip(id: target)
            Spacer(minLength: 4)
            Button {
                withAnimation(.smooth) { model.removeRemap(source) }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.62))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(KeyboardLayout.byID[source]?.name ?? source) mapping")
        }
        .padding(9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct KeyChip: View {
    let id: String

    var body: some View {
        Text(KeyboardLayout.byID[id]?.name ?? id)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: Macros

private struct MacrosPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MacroList().frame(width: 250)
            MacroEditor()
        }
        .frame(height: 276)
        .onAppear {
            if model.selectedMacro == nil { model.selectedMacro = model.profile.macros.first?.id }
        }
    }
}

private struct MacroList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Macros").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    withAnimation(.smooth) { model.addMacro() }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold)).frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("New macro")
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.profile.macros) { macro in
                        Button {
                            model.selectedMacro = macro.id
                            model.capturingTrigger = false
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill").foregroundStyle(KeyZone.magenta.glow)
                                Text(macro.name).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                                Spacer()
                                if let trigger = macro.trigger {
                                    Text(KeyboardLayout.byID[trigger]?.label ?? trigger)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                            }
                            .padding(10)
                            .background(model.selectedMacro == macro.id ? .white.opacity(0.16) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.selectedMacro == macro.id ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

private struct MacroEditor: View {
    @Environment(AppModel.self) private var model

    private var binding: Binding<Macro>? {
        guard let id = model.selectedMacro, model.profile.macros.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.profile.macros.first { $0.id == id } ?? Macro() },
            set: { updated in
                if let index = model.profile.macros.firstIndex(where: { $0.id == id }) { model.profile.macros[index] = updated }
            })
    }

    var body: some View {
        Group {
            if let macro = binding {
                MacroForm(macro: macro)
            } else {
                ContentUnavailableView {
                    Label("Create Your First Macro", systemImage: "bolt.horizontal.fill")
                } description: {
                    Text("Macros run on this Mac while AULA Studio is open.")
                } actions: {
                    Button("New Macro") { withAnimation(.smooth) { model.addMacro() } }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

private struct MacroForm: View {
    @Environment(AppModel.self) private var model
    @Binding var macro: Macro

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Macro name", text: $macro.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button {
                    model.capturingTrigger.toggle()
                } label: {
                    Label(model.capturingTrigger ? "Click a Key…" : (macro.trigger.flatMap { KeyboardLayout.byID[$0]?.name } ?? "Set Trigger Key"), systemImage: "keyboard")
                }
                .buttonStyle(.glass)
                .tint(model.capturingTrigger ? KeyZone.magenta.glow : nil)
                Stepper("Repeat \(macro.repeatCount)×", value: $macro.repeatCount, in: 1...50)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .fixedSize()
                Button(role: .destructive) {
                    withAnimation(.smooth) { model.deleteMacro(macro.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Delete macro")
            }
            if !model.macrosTrusted {
                Button {
                    model.requestAccessibility()
                } label: {
                    Label("Allow Accessibility so macros can type", systemImage: "hand.raised.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($macro.steps) { $step in
                        MacroStepRow(step: $step) {
                            withAnimation(.smooth) { macro.steps.removeAll { $0.id == step.id } }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                Button { add(.text) } label: { Label("Text", systemImage: "textformat") }
                Button { add(.key) } label: { Label("Key", systemImage: "command") }
                Button { add(.delay) } label: { Label("Delay", systemImage: "timer") }
            }
            .buttonStyle(.glass)
        }
    }

    private func add(_ kind: MacroStep.Kind) {
        withAnimation(.smooth) { macro.steps.append(MacroStep(kind: kind)) }
    }
}

private struct MacroStepRow: View {
    @Binding var step: MacroStep
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: step.kind == .text ? "textformat" : (step.kind == .key ? "command" : "timer"))
                .foregroundStyle(KeyZone.cyan.glow)
                .frame(width: 20)
            switch step.kind {
            case .text:
                TextField("Text to type", text: $step.text).textFieldStyle(.plain)
            case .key:
                Picker("Key", selection: $step.keyID) {
                    ForEach(KeyboardLayout.remappable.filter { $0.virtualKey != nil }) { key in
                        Text(key.name).tag(key.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                ModifierToggle(symbol: "⌘", name: "Command", isOn: $step.command)
                ModifierToggle(symbol: "⌃", name: "Control", isOn: $step.control)
                ModifierToggle(symbol: "⌥", name: "Option", isOn: $step.option)
                ModifierToggle(symbol: "⇧", name: "Shift", isOn: $step.shift)
                Spacer(minLength: 0)
            case .delay:
                Stepper("Wait \(step.delay) ms", value: $step.delay, in: 10...10000, step: 50)
                Spacer(minLength: 0)
            }
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.62))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove step")
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ModifierToggle: View {
    let symbol: String
    let name: String
    @Binding var isOn: Bool

    var body: some View {
        Button(symbol) { isOn.toggle() }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .bold))
            .frame(width: 26, height: 24)
            .foregroundStyle(isOn ? .black : .white)
            .background(isOn ? Color.white.opacity(0.9) : .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel(name)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
