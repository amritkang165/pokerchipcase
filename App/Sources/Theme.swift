import SwiftUI

/// The per-device appearance setting, stored as `@AppStorage("appearance")`.
enum Appearance: String, CaseIterable {
    case felt, dark, system

    var label: String {
        switch self {
        case .felt: "Felt"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .felt: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// The per-device card back, stored as `@AppStorage("cardBack")`. Its color is the same in every theme.
enum CardBack: String, CaseIterable {
    case red, blue, green, black, purple

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red: Color(hex: 0xb03a2e)
        case .blue: Color(hex: 0x1f4e8c)
        case .green: Color(hex: 0x1e6b45)
        case .black: Color(hex: 0x1c1c1e)
        case .purple: Color(hex: 0x5b3a8c)
        }
    }
}

/// Look tokens. The layout is the same for every theme; only these values change.
struct Theme: Sendable {
    /// The room around the table.
    var background: Color
    /// Ground of the screens away from the table: lists, forms and sheets.
    var screen: Color
    /// Inner and outer stop of the table's radial gradient.
    var surface: [Color]
    var rim: Color
    var accent: Color
    /// Tint for system-drawn UI in the window's scheme (alerts, dialogs), readable on its light or dark material.
    var formTint: Color
    var seat: Color
    var text: Color
    var muted: Color
    var fold: Color
    /// Exactly three chip colors.
    var chips: [Color]
    /// Inner frame and lattice of a card back, edge of a card face.
    var cardFrame: Color
    /// Card face background.
    var cardFace: Color
    /// Rank and the black suits on a card face.
    var cardText: Color
    /// Hearts and diamonds.
    var cardRed: Color

    static let felt = Theme(
        background: Color(hex: 0x3b2414), screen: Color(hex: 0x1d5e33), surface: [Color(hex: 0x2f8a4e), Color(hex: 0x1d5e33)], rim: Color(hex: 0x6b3f1d),
        accent: Color(hex: 0xe8c15a), formTint: Color(hex: 0x9a6b00), seat: .black.opacity(0.45), text: Color(hex: 0xf3e9d2), muted: Color(hex: 0xc9b99a),
        fold: Color(hex: 0x7a2a1f), chips: [Color(hex: 0xc0392b), Color(hex: 0x2c3e50), Color(hex: 0x27ae60)],
        cardFrame: .white, cardFace: Color(hex: 0xf3e9d2), cardText: .black, cardRed: Color(hex: 0xc0392b))

    static let dark = Theme(
        background: Color(hex: 0x0d0f14), screen: Color(hex: 0x0d0f14), surface: [Color(hex: 0x171a22), Color(hex: 0x171a22)], rim: Color(hex: 0x232733),
        accent: Color(hex: 0x38e1b0), formTint: Color(hex: 0x38e1b0), seat: Color(hex: 0x232733), text: Color(hex: 0xe8eaf0), muted: Color(hex: 0x8a90a2),
        fold: Color(hex: 0x2a2e3a), chips: [Color(hex: 0x38e1b0), Color(hex: 0x5b6cff), Color(hex: 0xff9f68)],
        cardFrame: Color(hex: 0x3a3f4d), cardFace: Color(hex: 0x232733), cardText: Color(hex: 0xe8eaf0), cardRed: Color(hex: 0xff6b6b))
}

extension EnvironmentValues {
    @Entry var theme: Theme = .felt
}

extension View {
    /// Sets the theme that matches the current color scheme, and its form tint.
    func themed() -> some View { modifier(Themed()) }

    /// Theme background, tint and navigation bar for a screen; the last modifier inside its `NavigationStack`.
    /// Both themes have dark grounds, so system controls take their dark style. The bar's background
    /// visibility is left to the screen: the table hides it from outside.
    func themedScreen() -> some View { modifier(ThemedScreen()) }

    /// The theme's seat color as the row background of a list or form section.
    func themedRow() -> some View { modifier(ThemedRow()) }
}

private struct ThemedScreen: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.screen.ignoresSafeArea())
            // No foregroundStyle, not even a hierarchical one: in a Form it overrides button tint and the
            // destructive role's red. Section headers set theme.muted themselves.
            .tint(theme.accent)
            .toolbarBackground(theme.screen, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .environment(\.colorScheme, .dark)
    }
}

private struct ThemedRow: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View { content.listRowBackground(theme.seat) }
}

private struct Themed: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme: Theme = scheme == .dark ? .dark : .felt
        content.environment(\.theme, theme).tint(theme.formTint)
    }
}

/// Full-width table button: accent fill for actions, the theme's fold color for Fold.
struct ThemeButtonStyle: ButtonStyle {
    enum Role { case primary, fold }
    var role: Role

    init(_ role: Role = .primary) { self.role = role }

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, role: role)
    }

    private struct Styled: View {
        let configuration: Configuration
        let role: Role
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.bold()).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(role == .fold ? theme.text : theme.background)
                .background(role == .fold ? theme.fold : theme.accent, in: .rect(cornerRadius: 10))
                .opacity(opacity)
        }

        private var opacity: Double {
            if !isEnabled { 0.4 } else if configuration.isPressed { 0.7 } else { 1 }
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}
