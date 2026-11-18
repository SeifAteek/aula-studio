import SwiftUI

struct KeyboardGeometry {
    static let margin = 0.66
    let unit: CGFloat
    let origin: CGPoint

    init(size: CGSize) {
        let totalWidth = KeyboardLayout.width + Self.margin * 2
        let totalHeight = KeyboardLayout.height + Self.margin * 2
        unit = max(min((size.width - 48) / totalWidth, (size.height - 44) / totalHeight), 1)
        origin = CGPoint(x: (size.width - unit * KeyboardLayout.width) / 2, y: (size.height - unit * KeyboardLayout.height) / 2)
    }

    var chassis: CGRect {
        CGRect(x: origin.x - unit * Self.margin, y: origin.y - unit * Self.margin,
               width: unit * (KeyboardLayout.width + Self.margin * 2), height: unit * (KeyboardLayout.height + Self.margin * 2))
    }

    func rect(_ key: KeyDef) -> CGRect {
        CGRect(x: origin.x + key.x * unit, y: origin.y + key.y * unit, width: key.w * unit, height: key.h * unit)
    }

    func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }

    func key(at location: CGPoint) -> KeyDef? { KeyboardLayout.keys.first { rect($0).contains(location) } }
}

private struct KeyboardSnapshot {
    let tab: StudioTab
    let lighting: LightingSettings
    let presses: [KeyPress]
    let remaps: [String: String]
    let triggers: Set<String>
    let mappingSource: String?
    let hovered: String?
    let capturing: Bool
}

struct KeyboardStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let geometry = KeyboardGeometry(size: proxy.size)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
                let snapshot = KeyboardSnapshot(
                    tab: model.tab, lighting: model.lighting, presses: model.presses, remaps: model.profile.remaps,
                    triggers: Set(model.profile.macros.compactMap(\.trigger)), mappingSource: model.mappingSource,
                    hovered: model.hoveredKey, capturing: model.capturingTrigger)
                Canvas { context, _ in
                    KeyboardRenderer.draw(in: context, geometry: geometry, now: AppClock.now(timeline.date), snapshot: snapshot)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                if let key = geometry.key(at: value.location) { model.tap(key) }
            })
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): model.hoveredKey = geometry.key(at: location)?.id
                case .ended: model.hoveredKey = nil
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("AULA F2058 keyboard preview")
            .accessibilityChildren {
                ForEach(KeyboardLayout.keys) { key in
                    Rectangle()
                        .accessibilityLabel(key.name)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.tap(key) }
                }
            }
        }
    }
}

private enum KeyboardRenderer {
    static func draw(in context: GraphicsContext, geometry g: KeyboardGeometry, now: Double, snapshot s: KeyboardSnapshot) {
        let u = g.unit
        let levels = litLevels(now: now, snapshot: s)

        // The keyboard casts colored light onto the desk behind it.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: u * 1.5))
            layer.blendMode = .plusLighter
            for key in KeyboardLayout.keys where levels[key.index] > 0.01 {
                layer.fill(Path(g.rect(key).insetBy(dx: -u * 0.5, dy: -u * 0.5)), with: .color(key.zone.glow.opacity(levels[key.index] * 0.16)))
            }
        }
        drawChassis(context, g)

        // Light stays inside the recessed plate, the way it does on the real keyboard.
        var plate = context
        var plateShape = Path()
        wellRects(g).forEach { plateShape.addRoundedRect(in: $0, cornerSize: CGSize(width: u * 0.14, height: u * 0.14), style: .continuous) }
        plate.clip(to: plateShape)
        plate.drawLayer { layer in
            layer.addFilter(.blur(radius: u * 0.2))
            layer.blendMode = .plusLighter
            for key in KeyboardLayout.keys where levels[key.index] > 0.01 {
                let path = Path(roundedRect: g.rect(key).insetBy(dx: u * 0.02, dy: u * 0.02), cornerRadius: u * 0.16)
                layer.fill(path, with: .color(key.zone.glow.opacity(levels[key.index] * 0.62)))
            }
        }
        plate.drawLayer { layer in
            layer.addFilter(.blur(radius: u * 0.09))
            layer.blendMode = .plusLighter
            for key in KeyboardLayout.keys where levels[key.index] > 0.01 {
                let path = Path(roundedRect: g.rect(key).insetBy(dx: u * 0.015, dy: u * 0.015), cornerRadius: u * 0.15)
                layer.stroke(path, with: .color(key.zone.glow.opacity(levels[key.index])), lineWidth: u * 0.06)
            }
        }

        for key in KeyboardLayout.keys { drawKey(context, g, key, lit: levels[key.index], snapshot: s, now: now) }
        drawControls(context, g, brightness: Double(s.lighting.brightness) / 13, now: now)
    }

    private static func wellRects(_ g: KeyboardGeometry) -> [CGRect] {
        [CGRect(x: -0.14, y: -0.14, width: 15.28, height: 1.28), CGRect(x: -0.14, y: 1.11, width: 15.28, height: 5.28),
         CGRect(x: 15.11, y: -0.14, width: 3.28, height: 1.28), CGRect(x: 15.11, y: 1.11, width: 3.28, height: 2.28),
         CGRect(x: 15.11, y: 4.11, width: 3.28, height: 2.28), CGRect(x: 18.36, y: 1.11, width: 4.28, height: 5.28)].map {
            CGRect(x: g.origin.x + $0.minX * g.unit, y: g.origin.y + $0.minY * g.unit, width: $0.width * g.unit, height: $0.height * g.unit)
        }
    }

    private static func litLevels(now: Double, snapshot s: KeyboardSnapshot) -> [Double] {
        guard s.tab == .lighting else {
            // Editing views use a calm, even glow so key labels and badges stay readable.
            return KeyboardLayout.keys.map { _ in 0.42 }
        }
        let info = EffectCatalog.info(s.lighting.effect)
        let presses = info.reactive ? s.presses + EffectEngine.demoPresses(now: now) : s.presses
        let brightness = pow(Double(s.lighting.brightness) / 13, 0.75)
        return KeyboardLayout.keys.map {
            EffectEngine.intensity(effect: s.lighting.effect, key: $0, now: now, speed: s.lighting.speed,
                                   slot: s.lighting.slot, presses: presses) * brightness
        }
    }

    private static func drawChassis(_ context: GraphicsContext, _ g: KeyboardGeometry) {
        let u = g.unit
        let body = Path(roundedRect: g.chassis, cornerRadius: u * 0.42, style: .continuous)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.75), radius: u * 0.85, x: 0, y: u * 0.5))
            layer.fill(body, with: .color(.black))
        }
        context.fill(body, with: .linearGradient(
            Gradient(stops: [.init(color: Color(white: 0.27), location: 0), .init(color: Color(white: 0.145), location: 0.14),
                             .init(color: Color(white: 0.09), location: 0.82), .init(color: Color(white: 0.17), location: 1)]),
            startPoint: CGPoint(x: g.chassis.midX, y: g.chassis.minY), endPoint: CGPoint(x: g.chassis.midX, y: g.chassis.maxY)))

        // Fine horizontal lines give the panel a brushed metal finish.
        var clipped = context
        clipped.clip(to: body)
        var brushed = Path()
        for y in stride(from: g.chassis.minY, to: g.chassis.maxY, by: max(u * 0.035, 1.5)) {
            brushed.move(to: CGPoint(x: g.chassis.minX, y: y))
            brushed.addLine(to: CGPoint(x: g.chassis.maxX, y: y))
        }
        clipped.stroke(brushed, with: .color(.white.opacity(0.018)), lineWidth: 0.5)
        clipped.fill(Path(CGRect(x: g.chassis.minX, y: g.chassis.minY, width: g.chassis.width, height: u * 0.72)),
                     with: .linearGradient(Gradient(colors: [.white.opacity(0.13), .clear]),
                                           startPoint: CGPoint(x: g.chassis.midX, y: g.chassis.minY),
                                           endPoint: CGPoint(x: g.chassis.midX, y: g.chassis.minY + u * 0.72)))

        context.stroke(body, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.62), .white.opacity(0.11), .white.opacity(0.26)]),
            startPoint: CGPoint(x: g.chassis.minX, y: g.chassis.minY), endPoint: CGPoint(x: g.chassis.maxX, y: g.chassis.maxY)),
            lineWidth: max(1, u * 0.025))

        for rect in wellRects(g) {
            let path = Path(roundedRect: rect, cornerRadius: u * 0.14, style: .continuous)
            context.fill(path, with: .color(Color(white: 0.018)))
            context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: max(0.75, u * 0.012))
        }

        let wordmark = context.resolve(Text(verbatim: "AULA").font(.system(size: u * 0.24, weight: .heavy, design: .rounded)).tracking(u * 0.05)
            .foregroundStyle(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.42)], startPoint: .top, endPoint: .bottom)))
        context.draw(wordmark, at: g.point(16.75, 3.72))
    }

    private static func drawKey(_ context: GraphicsContext, _ g: KeyboardGeometry, _ key: KeyDef, lit: Double, snapshot s: KeyboardSnapshot, now: Double) {
        let u = g.unit
        let cell = g.rect(key).insetBy(dx: u * 0.045, dy: u * 0.045)
        let skirt = Path(roundedRect: cell, cornerRadius: u * 0.13, style: .continuous)
        context.fill(skirt, with: .linearGradient(Gradient(colors: [Color(white: 0.16), Color(white: 0.035)]),
                                                  startPoint: CGPoint(x: cell.midX, y: cell.minY), endPoint: CGPoint(x: cell.midX, y: cell.maxY)))
        context.fill(skirt, with: .linearGradient(Gradient(colors: [.clear, key.zone.glow.opacity(lit * 0.72)]),
                                                  startPoint: CGPoint(x: cell.midX, y: cell.midY + cell.height * 0.1), endPoint: CGPoint(x: cell.midX, y: cell.maxY)))
        context.stroke(skirt, with: .color(key.zone.glow.opacity(lit * 0.72)), lineWidth: max(0.8, u * 0.022))

        let face = CGRect(x: cell.minX + u * 0.085, y: cell.minY + u * 0.05, width: cell.width - u * 0.17, height: cell.height - u * 0.2)
        let top = Path(roundedRect: face, cornerRadius: u * 0.1, style: .continuous)
        context.fill(top, with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.095)]),
                                                startPoint: CGPoint(x: face.minX, y: face.minY), endPoint: CGPoint(x: face.maxX, y: face.maxY)))
        context.stroke(top, with: .linearGradient(Gradient(colors: [.white.opacity(0.28), .white.opacity(0.03)]),
                                                  startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.maxY)),
                       lineWidth: max(0.7, u * 0.012))

        // Move the legend up so a mapping badge never covers it.
        let hasBadge = s.tab != .lighting && (s.triggers.contains(key.id) || s.remaps[key.id] != nil)
        drawLegend(context, g, key, face: face.offsetBy(dx: 0, dy: hasBadge ? -u * 0.12 : 0), lit: lit)
        drawBadge(context, g, key, face: face, snapshot: s)

        let isSource = s.mappingSource == key.id
        let isHovered = s.hovered == key.id && (s.tab != .lighting || key.canRemap)
        if isSource || isHovered {
            let pulse = isSource ? 0.68 + 0.32 * sin(now * 5) : 0.62
            context.stroke(skirt, with: .color(.white.opacity(pulse)), lineWidth: max(1.5, u * (isSource ? 0.05 : 0.03)))
        }
    }

    private static func drawLegend(_ context: GraphicsContext, _ g: KeyboardGeometry, _ key: KeyDef, face: CGRect, lit: Double) {
        guard !key.label.isEmpty else {
            var bar = Path()
            bar.addRoundedRect(in: CGRect(x: face.midX - g.unit * 0.3, y: face.midY - g.unit * 0.015, width: g.unit * 0.6, height: g.unit * 0.03),
                               cornerSize: CGSize(width: g.unit * 0.015, height: g.unit * 0.015))
            context.fill(bar, with: .color(key.zone.legend.opacity(0.18 + lit * 0.8)))
            return
        }
        let u = g.unit
        let color = key.zone.legend.opacity(0.26 + lit * 0.74)
        let size = u * (key.label.count == 1 ? 0.29 : (key.label.count > 4 ? 0.165 : 0.19))
        if let sub = key.sub {
            let upper = context.resolve(Text(verbatim: sub).font(.system(size: u * 0.17, weight: .semibold, design: .rounded)).foregroundStyle(color))
            let lower = context.resolve(Text(verbatim: key.label).font(.system(size: u * 0.23, weight: .bold, design: .rounded)).foregroundStyle(color))
            context.draw(upper, at: CGPoint(x: face.midX, y: face.midY - u * 0.13))
            context.draw(lower, at: CGPoint(x: face.midX, y: face.midY + u * 0.12))
        } else {
            let legend = context.resolve(Text(verbatim: key.label).font(.system(size: size, weight: .bold, design: .rounded)).foregroundStyle(color))
            context.draw(legend, at: CGPoint(x: face.midX, y: face.midY))
        }
    }

    private static func drawBadge(_ context: GraphicsContext, _ g: KeyboardGeometry, _ key: KeyDef, face: CGRect, snapshot s: KeyboardSnapshot) {
        guard s.tab != .lighting else { return }
        let u = g.unit
        let text: String
        let fill: Color
        if s.triggers.contains(key.id) {
            (text, fill) = ("Macro", KeyZone.magenta.glow)
        } else if let target = s.remaps[key.id], let name = KeyboardLayout.byID[target]?.label {
            (text, fill) = ("→ \(name.isEmpty ? "Space" : name)", KeyZone.cyan.glow)
        } else {
            return
        }
        let badge = CGRect(x: face.minX + u * 0.03, y: face.maxY - u * 0.25, width: face.width - u * 0.06, height: u * 0.25)
        context.fill(Path(roundedRect: badge, cornerRadius: u * 0.08, style: .continuous), with: .color(fill))
        let label = context.resolve(Text(verbatim: text).font(.system(size: u * 0.14, weight: .heavy, design: .rounded)).foregroundStyle(.black))
        context.draw(label, at: CGPoint(x: badge.midX, y: badge.midY))
    }

    private static func drawControls(_ context: GraphicsContext, _ g: KeyboardGeometry, brightness: Double, now: Double) {
        let u = g.unit
        for (index, name) in ["M1", "M2", "M3"].enumerated() {
            let center = g.point(19 + Double(index), 0.5)
            let rect = CGRect(x: center.x - u * 0.34, y: center.y - u * 0.34, width: u * 0.68, height: u * 0.68)
            context.fill(Path(ellipseIn: rect.insetBy(dx: -u * 0.05, dy: -u * 0.05)), with: .color(KeyZone.blue.glow.opacity(0.28 + brightness * 0.5)))
            context.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [Color(white: 0.76), Color(white: 0.25)]),
                                                                      startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            context.fill(Path(ellipseIn: rect.insetBy(dx: u * 0.05, dy: u * 0.05)), with: .linearGradient(
                Gradient(colors: [Color(white: 0.34), Color(white: 0.16)]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            let label = context.resolve(Text(verbatim: name).font(.system(size: u * 0.2, weight: .heavy, design: .rounded)).foregroundStyle(Color(white: 0.88)))
            context.draw(label, at: center)
        }

        let center = g.point(22, 0.5)
        let radius = u * 0.55
        let outer = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: outer), with: .conicGradient(
            Gradient(colors: [Color(white: 0.75), Color(white: 0.22), Color(white: 0.62), Color(white: 0.16), Color(white: 0.75)]), center: center))
        var knurl = Path()
        for tick in 0..<56 {
            let angle = Double(tick) / 56 * 2 * .pi
            knurl.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.84, y: center.y + sin(angle) * radius * 0.84))
            knurl.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        context.stroke(knurl, with: .color(.black.opacity(0.55)), lineWidth: max(0.7, u * 0.014))

        let ring = outer.insetBy(dx: radius * 0.24, dy: radius * 0.24)
        let spectrum: [Color] = [KeyZone.cyan, .green, .yellow, .red, .magenta, .blue, .cyan].map(\.glow)
        var glowing = context
        glowing.addFilter(.blur(radius: u * 0.055))
        glowing.blendMode = .plusLighter
        glowing.stroke(Path(ellipseIn: ring), with: .conicGradient(Gradient(colors: spectrum), center: center, angle: .radians(now * 0.5)),
                       lineWidth: u * 0.1)
        context.stroke(Path(ellipseIn: ring), with: .conicGradient(Gradient(colors: spectrum), center: center, angle: .radians(now * 0.5)),
                       lineWidth: u * 0.045)
        let cap = ring.insetBy(dx: u * 0.045, dy: u * 0.045)
        context.fill(Path(ellipseIn: cap), with: .radialGradient(Gradient(colors: [Color(white: 0.42), Color(white: 0.12)]), center: center, startRadius: 0, endRadius: cap.width))
        let sun = context.resolve(Image(systemName: "sun.max.fill"))
        var symbol = context
        symbol.opacity = 0.9
        symbol.draw(sun, in: cap.insetBy(dx: cap.width * 0.22, dy: cap.height * 0.22))

        for index in 0..<3 {
            let dot = g.point(17.75, 4.45 + Double(index) * 0.3)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - u * 0.09, y: dot.y - u * 0.05, width: u * 0.18, height: u * 0.1)), with: .color(KeyZone.magenta.glow.opacity(0.85)))
        }
    }
}
