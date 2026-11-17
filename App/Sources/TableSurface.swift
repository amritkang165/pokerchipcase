import SwiftUI

/// The table's ground: shadow, rail, cushion, felt and betting line. Fills the circle inscribed in its frame.
struct TableSurface: View {
    /// Rail width as a fraction of the diameter.
    private static let rail: CGFloat = 0.105
    /// Spacing of the wood grain rings as a fraction of the diameter.
    private static let grain: CGFloat = 0.0175

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                // Drop shadow, glow and rail in separate layers, bottom up: the glow lies over the
                // dark drop shadow instead of under it, and neither blurs the other.
                // The palette is picked from the scheme, so the scheme says whether the stage is dark.
                Circle().fill(railFill)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.35), radius: 0.07 * d, y: 0.04 * d)
                // An opaque fill: a translucent one would weaken the shadow by its own alpha.
                if let glow = theme.rail.glow { Circle().fill(railFill).shadow(color: glow, radius: 0.07 * d) }
                Circle().fill(railFill)
                    .overlay { relief }
                    .overlay { grain(d) }
                    .overlay { Circle().strokeBorder(theme.rail.edge, lineWidth: 1) }
                Circle().fill(theme.cushion).padding(Self.rail * d)
                // Lit from a lamp above the middle, darker toward the cushion.
                Circle()
                    .fill(RadialGradient(colors: theme.surface, center: UnitPoint(x: 0.5, y: 0.42),
                                         // The felt's own radius, so its edge gets the darkest stop (#132).
                                         startRadius: 0, endRadius: d * (0.5 - Self.rail - theme.cushionWidth))
                        .shadow(.inner(color: .black.opacity(0.4), radius: 0.03 * d)))
                    .padding((Self.rail + theme.cushionWidth) * d)
                Circle().stroke(theme.line, lineWidth: 1.5).frame(width: 0.37 * d, height: 0.37 * d)
            }
            .frame(width: d, height: d)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private var railFill: AnyShapeStyle {
        switch theme.rail.fill {
        case let .angular(colors, start):
            AnyShapeStyle(AngularGradient(colors: colors, center: .center, startAngle: start, endAngle: start + .degrees(360)))
        case let .linear(colors):
            AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    /// Light on the upper half, shade on the lower, so the rail reads as raised. The felt covers the middle.
    /// Neon's glowing rail stays flat.
    @ViewBuilder private var relief: some View {
        if theme.rail.glow == nil {
            Circle().fill(LinearGradient(
                stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .clear, location: 0.5),
                        .init(color: .black.opacity(0.3), location: 1)],
                startPoint: .top, endPoint: .bottom))
        }
    }

    /// Concentric rings across the rail, dropped where they would blur into one on a small table.
    @ViewBuilder private func grain(_ d: CGFloat) -> some View {
        if theme.rail.grain, Self.grain * d >= 2.5 {
            ForEach(1..<Int((Self.rail / Self.grain).rounded()), id: \.self) { i in
                Circle().strokeBorder(Color(hex: 0x2a1204).opacity(0.2), lineWidth: 1).padding(CGFloat(i) * Self.grain * d)
            }
        }
    }
}

/// The room behind the table: the theme's radial gradient, centered above the middle.
struct RoomBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let center = UnitPoint(x: 0.5, y: 0.38)
            // To the farthest corner, which is a bottom one since the center sits above the middle.
            let reach = hypot(geo.size.width / 2, geo.size.height * (1 - center.y))
            Rectangle().fill(RadialGradient(colors: theme.room, center: center, startRadius: 0, endRadius: reach))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))]) {
        ForEach(ThemeName.allCases, id: \.self) { name in
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                ZStack {
                    RoomBackground()
                    TableSurface().padding(8)
                    Text("\(name.label) \(scheme == .dark ? "dark" : "light")").font(.caption2).foregroundStyle(.white)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .aspectRatio(1, contentMode: .fit)
                .environment(\.theme, name.palette(for: scheme))
                .environment(\.colorScheme, scheme)
            }
        }
    }
    .padding()
}
